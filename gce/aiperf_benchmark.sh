#!/bin/bash
# aiperf_benchmark.sh - Benchmarking vLLM using NVIDIA aiperf

MODEL=""
TOKENIZER=""
URL="http://localhost:8000/v1/chat/completions"

# Setup uv environment
echo "Setting up benchmarking environment..."
if [ ! -d ".venv_aiperf" ]; then
    uv venv .venv_aiperf --python 3.12
fi
source .venv_aiperf/bin/activate

# Install aiperf if not installed
if ! command -v aiperf &> /dev/null; then
    echo "Installing aiperf from GitHub..."
    uv pip install "git+https://github.com/ai-dynamo/aiperf.git"
fi

# Auto-detect model if not provided
if [ -z "$MODEL" ]; then
    echo "Attempting to auto-detect model name from $URL..."
    MODELS_URL=$(echo "$URL" | sed 's|/chat/completions|/models|' | sed 's|/v1/chat/completions|/v1/models|')
    MODEL=$(curl -s "$MODELS_URL" | jq -r '.data[0].id' 2>/dev/null)
    if [ -z "$MODEL" ] || [ "$MODEL" == "null" ]; then
        echo "Warning: Could not auto-detect model name. Using 'default-model'."
        MODEL="default-model"
    else
        echo "Detected model: $MODEL"
    fi
fi

if [ -z "$TOKENIZER" ]; then
    # TODO: is this right - maybe not always
    TOKENIZER=$MODEL
fi

# Construct aiperf command
# Note: aiperf flags for synthetic input/output vary, using common ones.
# We pass --synthetic-input-tokens-mean and --synthetic-output-tokens-mean
# For shared prompt, we might need a custom dataset file or specific flag if supported.

# user centric testing - agentic 
# aiperf profile \
#    -m $MODEL \
#    --endpoint-type chat \
#    --streaming \
#    -u localhost:8000 \
#    --user-centric-rate 1.0 \
#    --num-users 5 \
#    --session-turns-mean 20 \
#    --shared-system-prompt-length 10000 \
#    --user-context-prompt-length 20000 \
#    --synthetic-input-tokens-mean 1000 \
#    --num-dataset-entries 1000 \
#    --benchmark-duration 100 \
#    --osl 200 \
#    --request-count 1000 \
#    --tokenizer $TOKENIZER 

#    --profile-export-file ${INPUT_SEQUENCE_LENGTH}_${OUTPUT_SEQUENCE_LENGTH}.json
#    --extra-inputs min_tokens:$OUTPUT_SEQUENCE_LENGTH \
#    --extra-inputs ignore_eos:true \
#    --synthetic-input-tokens-mean $INPUT_SEQUENCE_LENGTH \
#    --concurrency $CONCURRENCY \

aiperf profile \
   -m $MODEL \
   -u localhost:8000 \
   --shared-system-prompt-length 10000 \
   --user-context-prompt-length 1000 \
   --synthetic-input-tokens-mean 10 \
   --num-users 2 \
   --user-centric-rate 1.0 \
   --session-turns-mean 10 \
   --request-count 1000