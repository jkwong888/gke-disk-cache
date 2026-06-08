#!/bin/bash

# --- 1. Environment Setup ---
# SGLang requires a modern and isolated Python environment. We use Python 3.12 
# because it matches the vLLM environment and offers excellent compatibility 
# and performance with newer AI libraries.
echo "Setting up uv project..."
if [ ! -d ".venv" ]; then
    uv venv --python 3.12
fi

# We install sglang with the [runai] option to enable the RunAI streamer,
# which allows direct streaming of model weights from GCS buckets.
# This prevents downloading massive weights to the boot disk, significantly
# reducing the startup/cold-start latency of our VM. We also install lmcache
# so that the server can connect to a distributed KV cache if available.
echo "Installing SGLang and dependencies..."
uv pip install "sglang[runai]>=0.4.6" google-cloud-storage gcsfs lmcache

# --- 2. Input Validation & Model Setup ---
# The model path is required to tell SGLang what to load. We accept it as a positional
# argument to allow flexible invocations from external callers/startup tasks.
if [ -z "$1" ]; then
    echo "Error: MODEL_PATH argument is required."
    echo "Usage: $0 <MODEL_PATH>"
    exit 1
fi

MODEL_PATH="$1"

# The served model name identifies the model in the OpenAI-compatible API response.
# SGLang uses this to match client request formats. Extracting the last two parts
# (e.g., organization/model) keeps the naming consistent and clean.
MODEL_NAME=$(echo "$MODEL_PATH" | rev | cut -d/ -f1,2 | rev)

# --- 3. Google Cloud Project Auto-Discovery ---
# To support loading models directly from GCS without hardcoding, we query
# GCE's internal metadata server to discover the project-id dynamically.
export GOOGLE_CLOUD_PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
echo "Discovered project: $GOOGLE_CLOUD_PROJECT"

# Disable mTLS metadata server requests to bypass security-handshake stalls 
# inside Google's private virtual machine network.
export GCE_METADATA_MTLS_MODE=none

# --- 4. LMCache Integration ---
# If LMCache is configured and running, we enable the client's configuration
# pointing to its YAML definition and pass `--enable-lmcache` to SGLang.
# This enables sharing KV caches across multiple instances or requests,
# dramatically boosting Time-To-First-Token (TTFT) for recurring prompts.
if [ -f "lmcache_config.yaml" ]; then
    echo "discovered lmcache_config.yaml, setting LMCACHE_CONFIG_FILE"
    export LMCACHE_CONFIG_FILE="$PWD/lmcache_config.yaml"
fi

lmcache_pids=$(ps -ef | grep "lmcache server" | grep -v grep | wc -l)
if [ "$lmcache_pids" -gt 0 ]; then
    echo "detected lmcache server running"
    LMCACHE_CONFIG="--enable-lmcache"
fi

# --- 5. Start SGLang Inference Server ---
# We enable debug trace printing to trace arguments in the startup logs.
set -x
echo "Starting SGLang server..."

# Launching sglang.launch_server:
# - --model-path: Explicitly points SGLang to GCS or local model folder.
# - --served-model-name: Set to match the API expectation of client systems.
# - --load-format: Use runai_streamer for direct-to-GPU weight streaming from GCS.
# - --port: Server listens on 8000, aligning with the standard vLLM setup.
# - --mem-fraction-static: Allocates 95% of GPU memory for weights and KV cache,
#   ensuring maximum KV cache space while leaving a safety margin for activations.
# - --context-length: Maximum tokens (input + output). Equivalent to vLLM's max-model-len.
# - --tensor-parallel-size: Splits model across the specified number of GPUs.
# - --tool-call-parser: Parses specialized function-calling tags (e.g., for Gemma4)
#   back into standard OpenAI tool calls in API response.
# - --chunked-prefill-size / --max-num-batched-tokens: Optimizes context prefilling and
#   prevents Out-Of-Memory errors by chunking large requests into chunks of 8192 tokens.
# - --enable-kv-cache-cpu-backup / --enable-memory-saver: Offloads/backups the KV Cache
#   to system RAM to prevent VM crash/OOMs when total sequence context exceeds VRAM limit.
uv run python -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --served-model-name "$MODEL_NAME" \
    --load-format runai_streamer \
    --port 8000 \
    --model-loader-extra-config='{"distributed": true, "concurrency": 4}' \
    --mem-fraction-static 0.95 \
    --context-length 200000 \
    --tensor-parallel-size 1 \
    --tool-call-parser gemma4 \
    --chunked-prefill-size 8192 \
    --max-num-batched-tokens 8192 \
    --enable-kv-cache-cpu-backup \
    --enable-memory-saver \
    ${LMCACHE_CONFIG}
