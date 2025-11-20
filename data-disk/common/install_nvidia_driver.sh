echo "install nvidia drivers ..."
sudo systemctl stop google-cloud-ops-agent

curl -L https://storage.googleapis.com/compute-gpu-installation-us/installer/latest/cuda_installer.pyz --output cuda_installer.pyz
sudo python3 cuda_installer.pyz install_driver --installation-mode=binary
