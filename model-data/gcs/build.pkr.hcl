packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source = "github.com/hashicorp/googlecompute"
    }
  }
}

source "googlecompute" "model-data-build" {
  image_name                  = "${var.disk_name}-{{timestamp}}"
  project_id                  = var.project_id
  source_image_family         = "debian-12"
  zone                        = var.zone
  ssh_username                = "packer"
  tags                        = ["packer"]
  machine_type                = "e2-standard-8"
  # Disabling preemption for the model download/upload to avoid interruptions 
  # during the large (~60GB+) file transfers.
  preemptible                 = false

  disk_type                   = "pd-balanced"
  disk_size                   = var.disk_size
  skip_create_image           = true

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]

  omit_external_ip = true
  use_internal_ip = true
  use_iap = true

  network = var.network
  subnetwork = var.subnetwork
  network_project_id = var.network_project_id

}

build {
  sources = ["sources.googlecompute.model-data-build"]

  provisioner "shell" {
    inline = [
      "curl -LsSf https://astral.sh/uv/install.sh | sh",
      "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc",
    ]
  }

  provisioner "file" {
    source      = "download_weights_to_gcs.sh"
    destination = "/tmp/download_weights_to_gcs.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "MODELS=${join(" ", var.models)}",
      "GCS_BUCKET=${var.gcs_bucket}",
      "GCS_PREFIX=${var.gcs_prefix}",
      "HF_TOKEN=${var.hf_token}",
    ]
    inline = [
      "chmod +x /tmp/download_weights_to_gcs.sh",
      "/tmp/download_weights_to_gcs.sh"
    ]
  }
}
