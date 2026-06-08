#!/bin/bash

# 3. Setup vLLM project and dependencies
echo "Setting up uv project..."

if [ ! -d ".venv" ]; then
    uv venv --python 3.12
fi

# Install vLLM with RunAI streamer and GCS support
echo "Installing vLLM and dependencies..."
uv pip install "vllm[runai]" google-cloud-storage gcsfs

if [ -z "$1" ]; then
    echo "Error: MODEL_PATH argument is required."
    echo "Usage: $0 <MODEL_PATH>"
    exit 1
fi

MODEL_PATH="$1"
# Extract last two parts for served model name (e.g., org/model)
MODEL_NAME=$(echo "$MODEL_PATH" | rev | cut -d/ -f1,2 | rev)

# Discover Google Cloud project
export GOOGLE_CLOUD_PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
echo "Discovered project: $GOOGLE_CLOUD_PROJECT"

export GCE_METADATA_MTLS_MODE=none

# discover if lmcache_config.yaml exists
if [ -f "lmcache_config.yaml" ]; then
    echo "blahblah"
fi

# discover if lmcache is running
lmcache_pids=$(ps -ef | grep "lmcache server" | grep -v grep | wc -l)
if [ "$lmcache_pids" -gt 0 ]; then
    echo "detected lmcache server running"

    KV_TRANSFER_CONFIG="--kv-transfer-config='{"kv_connector":"LMCacheMPConnector","kv_role":"kv_both"}"
fi

set -x
echo "Starting vLLM server..."
uv run python -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name "$MODEL_NAME" \
    --load-format runai_streamer \
    --port 8000 \
    --model-loader-extra-config='{"distributed": true, "concurrency": 4}' \
    --gpu-memory-utilization 0.95 \
    --max-model-len 200000 \
    --tensor-parallel-size=1 \
    --enable-auto-tool-choice \
    --tool-call-parser gemma4 \
    --enable-chunked-prefill \
    --max-num-batched-tokens 8192 \
    --enable-prefix-caching \
    --no-disable-hybrid-kv-cache-manager \
    --kv-offloading-backend native \
    --kv-offloading-size 80
    # using host mem for offload kv cache, 80GB host mem
    # --kv-transfer-config='{"kv_connector":"MooncakeConnector","kv_role":"kv_both"}'
    # ${KV_TRANSFER_CONFIG}

# # minimax m2.7
# uv run python -m vllm.entrypoints.openai.api_server \
#     --model "$MODEL_PATH" \
#     --served-model-name "$MODEL_NAME" \
#     --load-format runai_streamer \
#     --port 8000 \
#     --tensor-parallel-size=2 \
#     --model-loader-extra-config='{"distributed": true, "concurrency": 4}' \
#     --compilation-config "{\"cudagraph_mode\": \"PIECEWISE\"}" \
#     --enable-auto-tool-choice \
#     --tool-call-parser minimax_m2 \
#     --reasoning-parser minimax_m2_append_think