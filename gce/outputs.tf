output "instance_name" {
  value = google_compute_instance.vllm_flex_vm.name
}

output "instance_zone" {
  value = google_compute_instance.vllm_flex_vm.zone
}

output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.vllm_flex_vm.name} --zone=${google_compute_instance.vllm_flex_vm.zone} --project=${var.project_id}"
}