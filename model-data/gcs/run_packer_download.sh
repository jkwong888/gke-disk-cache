#!/bin/bash
# Refactored script to download Hugging Face weights to GCS using Packer.
# Uses variables from variables.pkrvars.hcl and calculates required disk size.

set -e

# 1. Check HF_TOKEN
if [ -z "$HF_TOKEN" ]; then
    echo "Error: HF_TOKEN environment variable is not set."
    exit 1
fi

# 2. Check for Packer
if ! command -v packer &> /dev/null; then
    echo "Error: packer is not installed or not in PATH."
    exit 1
fi

# 3. Ensure uv is available locally for the size calculation
if ! command -v uv &> /dev/null; then
    echo "uv not found. Installing uv locally for this session..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# 4. Extract models from variables.pkrvars.hcl
# We use a simple python snippet to parse the HCL-like list
MODELS=$(python3 -c "
import re
import sys
try:
    with open('variables.pkrvars.hcl', 'r') as f:
        content = f.read()
    # Match models = [ ... ]
    match = re.search(r'models\s*=\s*\[(.*?)\]', content, re.DOTALL)
    if match:
        items = match.group(1).split(',')
        models = [i.strip().strip('\"').strip('\'') for i in items if i.strip()]
        print(' '.join(models))
except Exception as e:
    print(f'Error parsing models: {e}', file=sys.stderr)
    sys.exit(1)
")

if [ -z "$MODELS" ]; then
    echo "Error: Could not find models in variables.pkrvars.hcl"
    exit 1
fi

echo "Found models: $MODELS"

# 5. Calculate required disk size (max model size * 2.5 + 50GB buffer)
echo "Calculating required disk size..."

DISK_SIZE_GB=$(uv run --with huggingface_hub python3 -c "
import os
import sys
import math
from huggingface_hub import HfApi

token = os.environ.get('HF_TOKEN')
models = '$MODELS'.split()

max_size_gb = 0
for model_id in models:
    try:
        api = HfApi(token=token)
        info = api.model_info(repo_id=model_id, files_metadata=True)
        total_size_bytes = sum(sibling.size for sibling in info.siblings if sibling.size is not None)
        size_gb = total_size_bytes / (10**9)
        max_size_gb = max(max_size_gb, size_gb)
    except Exception as e:
        print(f'Warning: Error calculating size for {model_id}: {e}', file=sys.stderr)
        max_size_gb = max(max_size_gb, 150) # Fallback

# required disk size: We need space for CACHE + LOCAL_DIR + OS.
# 2.5x max_size_gb + 50GB buffer (min 150GB)
required_disk_gb = max(150, math.ceil(max_size_gb * 2.5) + 50)
print(required_disk_gb)
")

echo "Calculated required disk size: ${DISK_SIZE_GB}GB"
echo "Note: This large disk size ensures we have enough space for both the Hugging Face cache and the local directory during download."

# 6. Initialize and Run Packer
echo "Initializing Packer..."
packer init .

echo "Building Packer..."
# Note: hf_token is passed as a variable to Packer so it can be used in provisioners
packer build \
    -var-file="variables.pkrvars.hcl" \
    -var "disk_size=${DISK_SIZE_GB}" \
    -var "hf_token=${HF_TOKEN}" \
    .

echo "Process complete!"
