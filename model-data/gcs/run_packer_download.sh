#!/bin/bash
# Wrapper script to generate a Packer template dynamically based on model size
# and execute it to download Hugging Face weights to GCS.

set -e

# 1. Check required parameters and environment variables
if [ -z "$HF_TOKEN" ]; then
    echo "Error: HF_TOKEN environment variable is not set."
    echo "Please set it using: export HF_TOKEN='your_token'"
    exit 1
fi

MODEL_ID=$1
GCS_DESTINATION=$2

if [ -z "$MODEL_ID" ] || [ -z "$GCS_DESTINATION" ]; then
    echo "Usage: $0 <model_id> <gcs_destination_uri>"
    echo "Example: $0 meta-llama/Llama-2-7b-hf gs://jkwng-model-data/model-data"
    exit 1
fi

# 2. Set default GCP variables (can be overridden by environment)
PROJECT_ID=${PROJECT_ID:-"jkwng-kueue-dev"}
HOST_PROJECT_ID=${HOST_PROJECT_ID:-"jkwng-nonprod-vpc"}
ZONE=${ZONE:-"us-central1-c"}
NETWORK=${NETWORK:-"shared-vpc-nonprod-1"}
SUBNETWORK=${SUBNETWORK:-"kueue-dev"}

echo "Using GCP Project: $PROJECT_ID, Host Project: $HOST_PROJECT_ID, Zone: $ZONE, Network: $NETWORK, Subnet: $SUBNETWORK"

# 2.5 Validate Network Exists
echo "Validating network '$NETWORK' in host project '$HOST_PROJECT_ID'..."
if ! gcloud compute networks describe "$NETWORK" --project="$HOST_PROJECT_ID" &> /dev/null; then
    echo "Error: Network '$NETWORK' not found in project '$HOST_PROJECT_ID'."
    exit 1
fi
echo "Network validated successfully."

# 3. Calculate Model Size via Python
echo "Calculating model size for $MODEL_ID..."

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required to calculate model size."
    exit 1
fi

# Create a temporary virtual environment to keep the host clean
TEMP_VENV=$(mktemp -d)
python3 -m venv "$TEMP_VENV"
source "$TEMP_VENV/bin/activate"

# Ensure huggingface_hub is available in the virtualenv to query the size
pip install -q huggingface_hub

# Calculate the model size in bytes, convert to GB, and add 50GB buffer
DISK_SIZE_GB=$(python3 -c "
import os
import sys
import math
from huggingface_hub import HfApi

token = os.environ.get('HF_TOKEN')
model_id = '$MODEL_ID'

try:
    api = HfApi(token=token)
    info = api.model_info(repo_id=model_id, files_metadata=True)
    total_size_bytes = sum(sibling.size for sibling in info.siblings if sibling.size is not None)
    
    # Convert to GB (1 GB = 10**9 bytes)
    size_gb = total_size_bytes / (10**9)
    
    # Calculate required disk size (size_gb + 50GB buffer, min 100GB)
    required_disk_gb = max(100, math.ceil(size_gb) + 50)
    print(required_disk_gb)
except Exception as e:
    print(f'Error calculating size: {e}', file=sys.stderr)
    # Fallback to 200 if API call fails
    print(200)
")

# Clean up the temporary virtual environment
deactivate
rm -rf "$TEMP_VENV"

echo "Calculated required disk size: ${DISK_SIZE_GB}GB"

# 4. Generate the Packer Template dynamically
PACKER_FILE="download_weights.pkr.hcl"
echo "Generating Packer template: $PACKER_FILE"

# Ensure the Packer file is cleaned up on exit
trap "echo 'Cleaning up $PACKER_FILE...'; rm -f $PACKER_FILE" EXIT

cat <<EOF > "$PACKER_FILE"
packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

source "googlecompute" "weights_downloader" {
  project_id          = "${PROJECT_ID}"
  source_image_family = "debian-12"
  zone                = "${ZONE}"
  machine_type        = "e2-standard-8"
  preemptible         = true
  
  # Network config for private VM
  network             = "${NETWORK}"
  subnetwork          = "${SUBNETWORK}"
  network_project_id  = "${HOST_PROJECT_ID}"
  omit_external_ip    = true
  use_internal_ip     = true
  use_iap             = true
  
  # Disk configuration
  disk_size           = ${DISK_SIZE_GB}
  disk_type           = "pd-balanced"
  
  # We just want the VM to run the script and upload, no final image needed
  skip_create_image   = true
  
  # Default service account needs storage admin permissions
  scopes              = ["https://www.googleapis.com/auth/cloud-platform"]
  ssh_username        = "packer"
}

build {
  sources = ["source.googlecompute.weights_downloader"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y python3-venv python3-pip"
    ]
  }

  provisioner "file" {
    source      = "download_weights_to_gcs.sh"
    destination = "/tmp/download_weights_to_gcs.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "HF_TOKEN=${HF_TOKEN}",
      "MODEL_ID=${MODEL_ID}",
      "GCS_DESTINATION=${GCS_DESTINATION}",
      "PYTHONUNBUFFERED=1",
      "GCE_METADATA_MTLS_MODE=none"
    ]
    inline = [
      "chmod +x /tmp/download_weights_to_gcs.sh",
      "/tmp/download_weights_to_gcs.sh \"\$MODEL_ID\" \"\$GCS_DESTINATION\""
    ]
  }
}
EOF

echo "Packer template generated successfully."

# 5. Execute Packer
if ! command -v packer &> /dev/null; then
    echo "Error: packer is not installed or not in PATH."
    exit 1
fi

echo "Initializing Packer..."
packer init "$PACKER_FILE"

echo "Building Packer..."
packer build "$PACKER_FILE"

echo "Process complete!"
