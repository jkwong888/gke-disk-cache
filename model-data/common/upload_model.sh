#!/bin/bash

# MODEL_ID=${MODEL_ID}
# MOUNT_PATH=/mnt/disks/model-data
# MODEL_PREFIX=model-data
# BUCKET_ID=jkwng-model-data

echo "installing gcloud cli ..."
apt update
apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli

for MODEL_ID in ${MODELS}; do
    echo "writing model ${MODEL_ID} to ${MOUNT_PATH}/${MODEL_PREFIX} ..."
    gcloud storage rsync --recursive ${MOUNT_PATH}/${MODEL_PREFIX}/${MODEL_ID} gs://${GCS_BUCKET}/${GCS_PREFIX}/${MODEL_ID}
done