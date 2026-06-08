#!/bin/bash
# Script to download Hugging Face models and upload them to a GCS bucket
# This script is meant to be run inside a Packer-provisioned VM.

set -e

# 1. Check HF_TOKEN environment variable
if [ -z "$HF_TOKEN" ]; then
    echo "Error: HF_TOKEN environment variable is not set."
    exit 1
fi

# 2. Check parameters from environment
if [ -z "$MODELS" ]; then
    echo "Error: MODELS environment variable is not set (space-separated list)."
    exit 1
fi

if [ -z "$GCS_BUCKET" ] || [ -z "$GCS_PREFIX" ]; then
    echo "Error: GCS_BUCKET or GCS_PREFIX environment variable is not set."
    exit 1
fi

# Ensure uv is in PATH
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv &> /dev/null; then
    echo "Error: uv is not installed or not in PATH."
    exit 1
fi

echo "Setting up temporary environment using uv..."

# Create a temporary directory for the download and virtualenv
TMP_DIR=$(mktemp -d -t hf_download_XXXXXX)
VENV_DIR="$TMP_DIR/venv"
MODEL_DATA_DIR="$TMP_DIR/model_data"
HF_CACHE_DIR="$TMP_DIR/hf_cache"

# Make sure to clean up the temporary directory on script exit
trap "echo 'Cleaning up temporary directory...'; rm -rf $TMP_DIR" EXIT

mkdir -p "$MODEL_DATA_DIR" "$HF_CACHE_DIR"

# 4. Set up virtual environment and install dependencies
uv venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
uv pip install -q huggingface_hub google-cloud-storage hf_transfer

for MODEL_ID in $MODELS; do
    echo "========================================================="
    echo "Starting process for model: $MODEL_ID"
    echo "========================================================="
    
    # Export variables for the Python script
    export MODEL_ID="$MODEL_ID"
    export GCS_DESTINATION="gs://${GCS_BUCKET}/${GCS_PREFIX}"
    export MODEL_DATA_DIR="$MODEL_DATA_DIR"
    export HF_CACHE_DIR="$HF_CACHE_DIR"
    export HF_TOKEN="$HF_TOKEN"
    export HF_HUB_VERBOSITY=debug
    export PYTHONUNBUFFERED=1
    export GCE_METADATA_MTLS_MODE=none
    export HF_HUB_DISABLE_XET=1

    # Execute uploader Python script
    python3 -u - << 'EOF'
import os
import sys
import hashlib
import base64
import logging
import shutil
import time
import threading
from concurrent.futures import ThreadPoolExecutor
from huggingface_hub import snapshot_download
from google.cloud import storage

# Configure logging to be more verbose
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s %(levelname)s %(message)s')
logging.getLogger("urllib3").setLevel(logging.DEBUG)
logging.getLogger("requests").setLevel(logging.DEBUG)

# Parameters from env
MODEL_ID = os.environ.get('MODEL_ID')
GCS_DESTINATION = os.environ.get('GCS_DESTINATION')
HF_TOKEN = os.environ.get('HF_TOKEN')
LOCAL_DIR = os.environ.get('MODEL_DATA_DIR')
CACHE_DIR = os.environ.get('HF_CACHE_DIR')

def print_disk_usage(msg):
    usage = shutil.disk_usage("/")
    print(f"[DISK USAGE] {msg}: {usage.free / (1024**3):.2f} GB free out of {usage.total / (1024**3):.2f} GB total")

def monitor_download():
    """Monitors the local directory to show progress during snapshot_download."""
    last_size = 0
    while True:
        try:
            current_size = sum(os.path.getsize(os.path.join(dirpath, filename)) 
                               for dirpath, _, filenames in os.walk(LOCAL_DIR) 
                               for filename in filenames)
            diff = current_size - last_size
            if diff > 0:
                print(f"[PROGRESS] Downloaded {current_size / (1024**2):.2f} MB (+{diff / (1024**2):.2f} MB in last 60s)")
                sys.stdout.flush()
            last_size = current_size
        except:
            pass
        time.sleep(60)

if not GCS_DESTINATION.startswith("gs://"):
    print(f"Error: GCS_DESTINATION must start with gs:// (got {GCS_DESTINATION})")
    sys.exit(1)

parts = GCS_DESTINATION[5:].split("/", 1)
BUCKET_NAME = parts[0]
PREFIX = parts[1] if len(parts) > 1 else ""

if PREFIX:
    if not PREFIX.endswith('/'):
        PREFIX += '/'
    PREFIX = f"{PREFIX}{MODEL_ID}"
else:
    PREFIX = MODEL_ID

print(f"Uploading {MODEL_ID} to bucket: {BUCKET_NAME}, prefix: {PREFIX}")

def get_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            hash_md5.update(chunk)
    return hash_md5.digest()

def upload_file(file_path, bucket):
    try:
        rel_path = os.path.relpath(file_path, LOCAL_DIR)
        if any(part.startswith('.') for part in rel_path.split(os.sep)) or file_path.endswith(".lock"):
            return

        blob_name = f"{PREFIX}/{rel_path}"
        blob = bucket.blob(blob_name)

        if blob.exists():
            blob.reload()
            local_md5_b64 = base64.b64encode(get_md5(file_path)).decode('utf-8')
            if blob.md5_hash == local_md5_b64:
                print(f"[SKIP] {rel_path} - matches GCS")
                return

        print(f"[UPLOAD] {rel_path}...")
        blob.upload_from_filename(file_path, checksum="md5")
        print(f"[DONE] {rel_path}")

    except Exception as e:
        print(f"Error uploading {file_path}: {e}")
        raise

def main():
    print(f"Starting process for model: {MODEL_ID}")
    print_disk_usage("Before download")
    
    # Start monitor thread
    mon_thread = threading.Thread(target=monitor_download, daemon=True)
    mon_thread.start()

    print(f"Starting download of {MODEL_ID} to {LOCAL_DIR} with cache {CACHE_DIR} (HF_TOKEN length: {len(HF_TOKEN) if HF_TOKEN else 0})...")
    try:
        # Use more threads for downloading (max_workers=8 is hf default)
        snapshot_download(
            repo_id=MODEL_ID,
            local_dir=LOCAL_DIR,
            cache_dir=CACHE_DIR,
            token=HF_TOKEN,
            local_dir_use_symlinks=False,
            tqdm_class=None,  # Disable TQDM to avoid terminal garbage
            max_workers=4,
            etag_timeout=30

        )
    except Exception as e:
        print_disk_usage("After download failure")
        print(f"Error during snapshot_download: {e}")
        sys.exit(1)

    print_disk_usage("After download success")
    print(f"Download complete. Starting upload to gs://{BUCKET_NAME}/{PREFIX}...")
    
    storage_client = storage.Client()
    bucket = storage_client.bucket(BUCKET_NAME)
    
    files_to_upload = []
    for root, _, files in os.walk(LOCAL_DIR):
        for name in files:
            files_to_upload.append(os.path.join(root, name))

    with ThreadPoolExecutor(max_workers=16) as executor:
        list(executor.map(lambda f: upload_file(f, bucket), files_to_upload))

    print(f"Upload complete for {MODEL_ID}.")
    print_disk_usage("Final check after upload")

if __name__ == "__main__":
    main()
EOF

    # Clear directories after each model to save space for the next one
    rm -rf "${MODEL_DATA_DIR:?}"/*
    rm -rf "${HF_CACHE_DIR:?}"/*

    echo "Finished model: $MODEL_ID"
done

echo "All models processed successfully!"
