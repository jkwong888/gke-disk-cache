#!/bin/bash

set -x

# DISK_NAME=model-data
# MOUNT_PATH=/mnt/disks/${DISK_NAME}

DEVICE_NAME=$(readlink -f /dev/disk/by-id/google-${DISK_NAME})

echo "partitioning disk ${DISK_NAME} (${DEVICE_NAME}) ..."
sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard ${DEVICE_NAME}

echo "mounting ${DEVICE_NAME} to ${MOUNT_PATH} ..."
sudo mkdir -p ${MOUNT_PATH}
sudo mount -o discard,defaults ${DEVICE_NAME} ${MOUNT_PATH}
sudo chmod a+w ${MOUNT_PATH}