#!/bin/bash

IMAGE=vllm/vllm-openai:v0.20.0

MODEL_PATH="$1"
# Extract last two parts for served model name (e.g., org/model)
MODEL_NAME=$(echo "$MODEL_PATH" | rev | cut -d/ -f1,2 | rev)

# Discover Google Cloud project
export GOOGLE_CLOUD_PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
echo "Discovered project: $GOOGLE_CLOUD_PROJECT"

export GCE_METADATA_MTLS_MODE=none

docker pull ${IMAGE}

echo "Starting vLLM server..."
docker run \
    --rm \
    --runtime=nvidia \
    --gpus all \
    ${IMAGE} \
    serve \
    $MODEL_PATH" \
    --served-model-name "$MODEL_NAME" \
    --load-format runai_streamer \
    --port 8000 \
    --model-loader-extra-config='{"distributed": true}' \
    --max-model-len 200000