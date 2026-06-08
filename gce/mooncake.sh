#!/bin/bash

MOUNTPOINT=/mnt/ssd

sudo apt-get update && sudo apt-get install -y --no-install-recommends bc rdma-core libibverbs1 libnuma1

echo "Setting up uv project..."
if [ ! -d ".venv" ]; then
    uv venv --python 3.12
fi

# Install lmcache
echo "Installing mooncake and dependencies..."
uv pip install mooncake-transfer-engine

# get free mem 
TOTAL_MEM_SIZE=$(free -g | grep "Mem:" | awk -F' ' '{print $2;}')
# use 50% of it for kvcache
MAX_MEM_SIZE=$(echo "${TOTAL_MEM_SIZE} * 0.5" | bc -l)

# get free space
MAX_DISK_SIZE=$(df -BG ${MOUNTPOINT} | grep ${MOUNTPOINT} | awk -F' ' '{print $4;}' | sed -e 's/G//')
