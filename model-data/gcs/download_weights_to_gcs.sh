#!/bin/bash
# Script to download a Hugging Face model and upload it to a GCS bucket

set -e

# 1. Check HF_TOKEN environment variable
if [ -z "$HF_TOKEN" ]; then
    echo "Error: HF_TOKEN environment variable is not set."
    echo "Please set it using: export HF_TOKEN='your_token'"
    exit 1
fi

# 2. Check parameters
MODEL_ID=$1
GCS_DESTINATION=$2

if [ -z "$MODEL_ID" ] || [ -z "$GCS_DESTINATION" ]; then
    echo "Usage: $0 <model_id> <gcs_destination_uri>"
    echo "Example: $0 meta-llama/Llama-2-7b-hf gs://jkwng-model-data/model-data"
    exit 1
fi

# 3. Check dependencies
if ! python3 -m venv --help &> /dev/null; then
    echo "Error: python3-venv is not installed. Please install it (e.g., sudo apt-get install python3-venv)."
    exit 1
fi

echo "Setting up temporary environment..."

# Create a temporary directory for the download and virtualenv
TMP_DIR=$(mktemp -d -t hf_download_XXXXXX)
VENV_DIR="$TMP_DIR/venv"
MODEL_DATA_DIR="$TMP_DIR/model_data"
HF_CACHE_DIR="$TMP_DIR/hf_cache"

# Make sure to clean up the temporary directory on exit (success or failure)
trap "echo 'Cleaning up temporary directory...'; rm -rf $TMP_DIR" EXIT

mkdir -p "$MODEL_DATA_DIR" "$HF_CACHE_DIR"

# 4. Set up virtual environment and install dependencies
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q huggingface_hub google-cloud-storage

echo "Starting async download and upload process for $MODEL_ID..."

export MODEL_ID="$MODEL_ID"
export GCS_DESTINATION="$GCS_DESTINATION"
export MODEL_DATA_DIR="$MODEL_DATA_DIR"
export HF_CACHE_DIR="$HF_CACHE_DIR"
export PYTHONUNBUFFERED=1
export GCE_METADATA_MTLS_MODE=none

# Discover Google Cloud project if not set
if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    if command -v gcloud &> /dev/null; then
        echo "Discovering Google Cloud Project using gcloud..."
        export GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
    fi
fi

if [ -n "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Using Google Cloud Project: $GOOGLE_CLOUD_PROJECT"
else
    echo "Warning: GOOGLE_CLOUD_PROJECT is not set and could not be determined."
fi

# 5. Run the embedded Python script for async processing
"$VENV_DIR/bin/python3" -u - << 'EOF'
import os
import sys
import time
import asyncio
import hashlib
import threading
import base64
import logging
from concurrent.futures import ThreadPoolExecutor
from huggingface_hub import snapshot_download
from google.cloud import storage

# Configure debug logging for Google libraries
logging.basicConfig(level=logging.INFO)
# Un-comment the following to see raw HTTP requests if INFO isn't enough
# logging.getLogger('google.auth').setLevel(logging.DEBUG)
# logging.getLogger('google.cloud').setLevel(logging.DEBUG)
# logging.getLogger('urllib3').setLevel(logging.DEBUG)

# Parameters from env
MODEL_ID = os.environ.get('MODEL_ID')
GCS_DESTINATION = os.environ.get('GCS_DESTINATION')
HF_TOKEN = os.environ.get('HF_TOKEN')
LOCAL_DIR = os.environ.get('MODEL_DATA_DIR')
CACHE_DIR = os.environ.get('HF_CACHE_DIR')

# Debug info for environment variables (proxies, GCP projects, etc.)
print("--- DEBUG: Environment Settings ---")
for k, v in os.environ.items():
    k_upper = k.upper()
    if any(x in k_upper for x in ["PROXY", "HTTP", "GOOGLE", "PROJECT", "GCP"]):
        if "TOKEN" not in k_upper and "KEY" not in k_upper and "SECRET" not in k_upper:
            print(f"{k}: {v}")
print("-----------------------------------", flush=True)

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

print(f"Uploading to bucket: {BUCKET_NAME}, prefix: {PREFIX}")

# Function to check if any part of the path is hidden (starts with .)
def is_hidden(path):
    parts = path.split(os.sep)
    return any(p.startswith('.') for p in parts)

def get_storage_client(retries=5, delay=5):
    for i in range(retries):
        try:
            return storage.Client()
        except Exception as e:
            if i == retries - 1:
                raise
            print(f"Failed to create GCS client (attempt {i+1}/{retries}): {e}. Retrying in {delay}s...")
            time.sleep(delay)

storage_client = get_storage_client()
bucket = storage_client.bucket(BUCKET_NAME)

def get_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.digest()

def check_and_upload(file_path):
    try:
        rel_path = os.path.relpath(file_path, LOCAL_DIR)
        
        # Ignore hidden files or lock files
        if is_hidden(rel_path) or file_path.endswith(".lock"):
            return

        # Wait until file size is stable to ensure it is completely written
        last_size = -1
        missing_retries = 0
        zero_retries = 0
        while True:
            try:
                current_size = os.path.getsize(file_path)
                missing_retries = 0
            except OSError:
                missing_retries += 1
                if missing_retries > 10:
                    print(f"File {file_path} disappeared, skipping.")
                    return
                time.sleep(0.5)
                continue
                
            if current_size == last_size:
                if current_size == 0 and zero_retries < 5:
                    zero_retries += 1
                    time.sleep(0.5)
                    continue
                
                # Also wait briefly to make sure the handle is closed
                time.sleep(0.5)
                break
                
            last_size = current_size
            zero_retries = 0
            time.sleep(1.0)

        blob_name = f"{PREFIX}/{rel_path}"
        blob = bucket.blob(blob_name)

        # Retry loop for file upload and checksum check
        max_upload_retries = 5
        for attempt in range(max_upload_retries):
            try:
                if blob.exists():
                    blob.reload()
                    local_md5_bytes = get_md5(file_path)
                    local_md5_b64 = base64.b64encode(local_md5_bytes).decode('utf-8')
                    if blob.md5_hash == local_md5_b64:
                        print(f"[SKIP] {rel_path} - Checksum matches (MD5: {local_md5_b64})")
                        os.remove(file_path)
                        return
                    else:
                        print(f"[UPLOAD] {rel_path} - Checksum mismatch")
                else:
                    print(f"[UPLOAD] {rel_path} - File not in GCS")

                file_size = os.path.getsize(file_path)
                print(f"Uploading {file_path} to gs://{BUCKET_NAME}/{blob_name} ({file_size / (1024*1024):.2f} MB)... (attempt {attempt+1}/{max_upload_retries})")
                
                # Simple progress logger
                last_reported_time = time.time()
                def progress_callback(bytes_sent):
                    nonlocal last_reported_time
                    now = time.time()
                    if now - last_reported_time > 5: # Log every 5 seconds
                        percent = (bytes_sent / file_size) * 100
                        print(f"  [PROGRESS] {rel_path}: {percent:.1f}% ({bytes_sent/(1024*1024):.1f} MB sent)")
                        last_reported_time = now

                blob.upload_from_filename(file_path, checksum="md5")
                
                print(f"[DONE] {rel_path} uploaded successfully.")
                
                os.remove(file_path)
                print(f"[DELETED] Local file {rel_path} removed.")
                return

            except Exception as e:
                if attempt == max_upload_retries - 1:
                    raise
                print(f"Error uploading {file_path} (attempt {attempt+1}/{max_upload_retries}): {e}. Retrying in 10s...")
                time.sleep(10)

    except Exception as e:
        print(f"Error processing {file_path}: {e}")
    finally:
        with active_uploads_lock:
            active_uploads.discard(rel_path)

active_uploads = set()
active_uploads_lock = threading.Lock()
upload_queue = asyncio.Queue()

async def uploader_worker(executor):
    while True:
        try:
            file_path = await upload_queue.get()
            if file_path is None:
                upload_queue.task_done()
                break
            await asyncio.get_running_loop().run_in_executor(executor, check_and_upload, file_path)
            upload_queue.task_done()
        except Exception as e:
            print(f"Worker error: {e}")

def run_snapshot_download():
    print(f"Starting snapshot_download for {MODEL_ID}...")
    try:
        snapshot_download(
            repo_id=MODEL_ID,
            local_dir=LOCAL_DIR,
            cache_dir=CACHE_DIR,
            token=HF_TOKEN,
            local_dir_use_symlinks=False
        )
        print("snapshot_download finished.")
    except Exception as e:
        print(f"Error during snapshot_download: {e}")

async def scan_directory():
    for root, dirs, files in os.walk(LOCAL_DIR):
        # Skip hidden directories in-place
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for name in files:
            full_path = os.path.join(root, name)
            rel_path = os.path.relpath(full_path, LOCAL_DIR)
            # Basic filtering matches what's in check_and_upload
            if is_hidden(rel_path) or full_path.endswith(".lock"):
                continue
                
            with active_uploads_lock:
                if rel_path not in active_uploads:
                    active_uploads.add(rel_path)
                    await upload_queue.put(full_path)

async def main():
    global loop
    loop = asyncio.get_running_loop()

    executor = ThreadPoolExecutor(max_workers=8)
    num_workers = 8
    workers = [asyncio.create_task(uploader_worker(executor)) for _ in range(num_workers)]

    download_thread = threading.Thread(target=run_snapshot_download)
    download_thread.start()

    # Poll directory while downloading
    while download_thread.is_alive():
        await scan_directory()
        await asyncio.sleep(2)

    # Wait for the download thread to finish completely
    download_thread.join()
    
    # Final directory scan to catch anything that was written right at the end
    print("Download finished, performing final directory scan...")
    await scan_directory()

    print(f"Waiting for {upload_queue.qsize()} uploads to complete...")
    await upload_queue.join()
    
    print("All uploads completed, shutting down workers...")
    for _ in range(num_workers):
        await upload_queue.put(None)
    await asyncio.gather(*workers)

if __name__ == "__main__":
    asyncio.run(main())
EOF

echo "Async download and upload complete!"
