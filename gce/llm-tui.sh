#!/bin/bash

# Update package list and install prerequisites
sudo apt-get update
sudo apt-get install -y git curl apt-transport-https ca-certificates jq build-essential libssl-dev pkg-config

# Install Rust and Cargo
if ! command -v cargo &> /dev/null
then
    echo "Rust/Cargo not found. Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "Rust installed successfully."
else
    echo "Rust/Cargo is already installed: $(cargo -V)"
fi

# Install llm-tui-rs using cargo
echo "Installing llm-tui-rs..."
cargo install llm-tui-rs

# Query the running vLLM for the model name
echo "Querying local vLLM for running model..."
MODEL_NAME=""
# Try for up to 60 seconds to get the model from vLLM
for i in {1..12}; do
  RESPONSE=$(curl -s http://localhost:8000/v1/models)
  if [ -n "$RESPONSE" ]; then
    MODEL_NAME=$(echo $RESPONSE | jq -r '.data[0].id')
    if [ "$MODEL_NAME" != "null" ] && [ -n "$MODEL_NAME" ]; then
      break
    fi
  fi
  echo "Waiting for vLLM to be ready on port 8000..."
  sleep 5
done

if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" == "null" ]; then
  echo "Warning: Could not fetch model name from vLLM. Defaulting to 'meta-llama/Llama-2-7b-chat-hf'"
  MODEL_NAME="meta-llama/Llama-2-7b-chat-hf"
else
  echo "Detected model: $MODEL_NAME"
fi

# Create llm-tui configuration file
echo "Configuring llm-tui..."
mkdir -p ~/.config/llm-tui
cat <<EOF > ~/.config/llm-tui/config.toml
default_provider = "local-vllm"

[providers.local-vllm]
type = "openai_compatible"
base_url = "http://localhost:8000/v1"
api_key = "dummy-api-key"
model = "$MODEL_NAME"
EOF

# Configure llm-tui-rs environment variables (as fallback)
export OPENAI_API_BASE="http://localhost:8000/v1"
export OPENAI_API_KEY="dummy-api-key"
export LLM_TUI_MODEL="$MODEL_NAME"

echo "llm-tui configured to connect to local vLLM with model $MODEL_NAME."
echo "Starting llm-tui-rs..."

# Start llm-tui
~/.cargo/bin/llm-tui
