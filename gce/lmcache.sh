#!/bin/bash

MOUNTPOINT=/mnt/ssd

sudo apt-get update && sudo apt-get install -y --no-install-recommends bc

echo "Setting up uv project..."
if [ ! -d ".venv" ]; then
    uv venv --python 3.12
fi

# Install lmcache
echo "Installing lmcache and dependencies..."
uv pip install lmcache vllm openai

# get free mem 
TOTAL_MEM_SIZE=$(free -g | grep "Mem:" | awk -F' ' '{print $2;}')
# use 50% of it for kvcache
MAX_MEM_SIZE=$(echo "${TOTAL_MEM_SIZE} * 0.5" | bc -l)

# get free space
MAX_DISK_SIZE=$(df -BG ${MOUNTPOINT} | grep ${MOUNTPOINT} | awk -F' ' '{print $4;}' | sed -e 's/G//')

# generate LMCache Config
cat << EOF > lmcache_config.yaml 
chunk_size: 256
local_cpu: True
max_local_cpu_size: ${MAX_MEM_SIZE}

local_disk: "file://${MOUNTPOINT}/lmcache"
max_local_disk_size: ${MAX_DISK_SIZE}
extra_config: {'use_odirect': True}
EOF

set -x
uv run lmcache server \
    --eviction-policy LRU \
    --engine-type blend \
    --l1-size-gb ${MAX_MEM_SIZE} \
    --l2-adapter '{"type": "fs", "base_path": "'${MOUNTPOINT}'/lmcache"}'
    # TODO: nixl store
    # --l2-adapter '{"type": "nixl_store", "backend": "POSIX", "backend_params": {"file_path": "'${MOUNTPOINT}'/lmcache", "use_direct_io": "false"}, "pool_size": 64}'
