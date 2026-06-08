#!/bin/bash
exec > /var/log/startup-script.log 2>&1
set -x

# Ensure non-interactive apt installations
export DEBIAN_FRONTEND=noninteractive

# Function to wait for apt lock
wait_for_apt() {
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    echo "Waiting for other apt-get instances to finish..."
    sleep 5
  done
}

# 1. Install Python and dependencies
echo "Installing Python and tools..."
wait_for_apt
apt-get update || true
apt-get install -y python3-pip python3-venv curl wget git pciutils apt-transport-https ca-certificates gnupg linux-headers-$(uname -r)|| true

# 2. Install Docker CE
echo "Installing Docker CE..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc || true
if [ -f /etc/apt/keyrings/docker.asc ]; then
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    wait_for_apt
    apt-get update || true
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
fi

# 3. Install gcloud CLI
echo "Installing gcloud CLI..."
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg || true
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
wait_for_apt
apt-get update || true
apt-get install -y google-cloud-cli || true

# 4. Install uv
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv_install.sh || echo "Failed to download uv install script"
if [ -f /tmp/uv_install.sh ]; then
    env UV_INSTALL_DIR="/usr/local/bin" sh /tmp/uv_install.sh || echo "uv installation failed"
fi

# 5. Prepare Local SSDs if they exist
echo "Checking for Local SSDs..."
SSDS=$(find /dev/disk/by-id/ -name "google-local-nvme-ssd*")
SSD_COUNT=$(echo "$SSDS" | grep -c "google-local-nvme-ssd" || echo 0)

if [ "$SSD_COUNT" -gt 0 ]; then
    echo "Found $SSD_COUNT Local SSD(s). Preparing /mnt/ssd..."
    mkdir -p /mnt/ssd

    if [ "$SSD_COUNT" -gt 1 ]; then
        echo "Multiple SSDs found. Creating RAID 0 array..."
        wait_for_apt
        apt-get update && apt-get install -y mdadm --no-install-recommends
        
        # Create RAID 0 array /dev/md0
        # Use --force and --run to handle cases where it might be already partially initialized
        mdadm --create /dev/md0 --level=0 --raid-devices=$SSD_COUNT $SSDS --force --run
        DEVICE="/dev/md0"
        
        # Save mdadm config for reboots
        mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
        update-initramfs -u
    else
        echo "Single SSD found."
        DEVICE=$(echo "$SSDS" | head -n 1)
    fi

    # Format if not already formatted
    if ! blkid "$DEVICE" | grep -q "TYPE=\"ext4\""; then
        echo "Formatting $DEVICE with ext4..."
        mkfs.ext4 -F "$DEVICE"
    fi

    # Mount the device
    mount "$DEVICE" /mnt/ssd
    chmod a+w /mnt/ssd

    # Add to fstab for persistence
    UUID=$(blkid -s UUID -o value "$DEVICE")
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID /mnt/ssd ext4 discard,defaults,nofail 0 2" | tee -a /etc/fstab
    fi
    echo "Local SSD(s) mounted at /mnt/ssd"
else
    echo "No Local SSDs found. Skipping SSD preparation."
fi

# 6. install nvidia container toolkit
echo "Installing nvidia container toolkit..."
wait_for_apt
apt-get update && apt-get install -y --no-install-recommends \
   ca-certificates \
   curl \
   gnupg2
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.0-1
apt-get install -y \
    nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
    libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

### after this, to run a container using the gpu,
# docker run -rm --runtime=nvidia --gpus all <the rest of the command>

# 7. Conditionally Install NVIDIA drivers via systemd
if lspci | grep -i "nvidia" > /dev/null; then
    echo "NVIDIA GPU detected. Setting up systemd service for driver installation..."

    # Create the wrapper script for the systemd service
    cat << 'EOF' > /usr/local/bin/install_gpu_driver_service.sh
#!/bin/bash
exec >> /var/log/gpu-installer-service.log 2>&1
set -x

CUDA_INSTALL_DIR="/opt/google/cuda-installer"

# Prepare the environment and mark start
mkdir -p "${CUDA_INSTALL_DIR}"
cd "${CUDA_INSTALL_DIR}" || exit

# Only download if it doesn't already exist
if [ ! -f "cuda_installer.pyz" ]; then
    echo "Downloading Google's GPU installation script (cuda_installer.pyz)..."
    curl -fSsL -O https://storage.googleapis.com/compute-gpu-installation-us/installer/latest/cuda_installer.pyz
fi

echo "Running GPU installation script..."
python3 cuda_installer.pyz install_cuda --installation-mode=binary --installation-branch=prod
EOF

    chmod +x /usr/local/bin/install_gpu_driver_service.sh

    # Define the systemd service
    cat << 'EOF' > /etc/systemd/system/gpu-installer.service
[Unit]
Description=NVIDIA GPU Driver Installer
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/install_gpu_driver_service.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Register and trigger the service
    systemctl daemon-reload
    systemctl enable gpu-installer.service
    systemctl start gpu-installer.service

else
    echo "No NVIDIA GPU detected. Skipping driver installation."
fi

echo "Installation complete!"