packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1"
      source = "github.com/hashicorp/googlecompute"
    }
  }
}

source "googlecompute" "image-data-build" {
  image_name                  = "${var.disk_name}-{{timestamp}}"
  project_id                  = var.project_id
  source_image_family         = "debian-12"
  zone                        = var.zone
  ssh_username                = "packer"
  tags                        = ["packer"]
  machine_type                = "e2-standard-4"
  # preemptible                 = true
  # on_host_maintenance         = "TERMINATE"

  disk_type                   = "pd-balanced"
  disk_size                   = 100
#   impersonate_service_account = var.builder_sa

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]

  omit_external_ip = true
  use_internal_ip = true
  use_iap = true

  network = var.network
  subnetwork = var.subnetwork

  # NOTE the script depends on the secondary disk being named this
  disk_attachment {
    device_name = "secondary-disk-image-disk"  
    volume_type = "pd-balanced"
    volume_size = 60
    create_image = true
  }
}

build {
  sources = ["sources.googlecompute.image-data-build"]

  # copy the script
  provisioner "file" {
    source = "common/prepare_images.sh"
    destination = "/tmp/prepare_images.sh"
  }


  # prepare image data
  provisioner "shell" {
    inline = [
      "echo \"\n\nunpack false none ${join(" ", var.images)}\" >> /tmp/prepare_images.sh",
      "chmod +x /tmp/prepare_images.sh",
      "/bin/bash /tmp/prepare_images.sh"
    ]
  }

}