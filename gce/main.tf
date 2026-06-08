provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_project" "project" {
  project_id = var.project_id
}

data "google_project" "vpc_host_project" {
  project_id = var.vpc_host_project
}

data "google_compute_network" "vpc_network" {
  name    = var.network_name
  project = data.google_project.vpc_host_project.project_id
}

data "google_compute_subnetwork" "vpc_subnetwork" {
  name    = var.subnetwork_name
  region  = var.region
  project = data.google_project.vpc_host_project.project_id
}

resource "google_compute_instance" "vllm_flex_vm" {
  project      = data.google_project.project.project_id
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      size  = var.disk_size
      type  = var.disk_type
    }
  }

  dynamic "scratch_disk" {
    for_each = range(var.local_ssd_count)
    content {
      interface = var.local_ssd_interface
    }
  }

  network_interface {
    # Utilizing Shared VPC parameters validated via data sources
    network    = data.google_compute_network.vpc_network.id
    subnetwork = data.google_compute_subnetwork.vpc_subnetwork.id
  }

  scheduling {
    provisioning_model          = var.provisioning_model
    instance_termination_action = var.provisioning_model == "STANDARD" ? null : "DELETE"
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = var.provisioning_model == "STANDARD" ? true : false
    preemptible                 = var.provisioning_model == "SPOT" ? true : false


    # 168 hours = 604,800 seconds
    dynamic "max_run_duration" {
      for_each = var.provisioning_model == "FLEX_START" ? [1] : []
      content {
        seconds = 604800
      }
    }
  }

  # Conditionally attach GPU based on gpu_count variable
  dynamic "guest_accelerator" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  metadata = {
    model-path     = var.model_path
    startup-script = file("${path.module}/startup.sh")
  }

  service_account {
    # Default compute service account with Cloud Platform scope to access GCS
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "null_resource" "wait_for_ssh" {
  triggers = {
    instance_id = google_compute_instance.vllm_flex_vm.id
  }

  provisioner "local-exec" {
    command = "while ! gcloud compute ssh --project ${data.google_project.project.project_id} --zone ${var.zone} ${var.vm_name} --command 'echo SSH Ready' --quiet; do sleep 5; done"
  }
}

resource "null_resource" "sync_scripts" {
  for_each = toset(var.sync_scripts)

  triggers = {
    # Trigger if the specific script content changes
    script_hash = filemd5("${path.module}/${each.value}")
    # Trigger if the VM is recreated
    instance_id = google_compute_instance.vllm_flex_vm.id
  }

  provisioner "local-exec" {
    command = "gcloud compute scp --project ${data.google_project.project.project_id} --zone ${var.zone} ${path.module}/${each.value} ${var.vm_name}:~/"
  }

  depends_on = [null_resource.wait_for_ssh]
}