variable "provisioning_model" {
  description = "The provisioning model for the instance (STANDARD, SPOT, or FLEX_START)"
  type        = string
  default     = "FLEX_START"
  validation {
    condition     = contains(["STANDARD", "SPOT", "FLEX_START"], var.provisioning_model)
    error_message = "The provisioning_model must be STANDARD, SPOT, or FLEX_START."
  }
}

variable "project_id" {
  description = "The GCP project ID to deploy resources into"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "zone" {
  description = "The GCP zone (must support H100/A3 capacity)"
  type        = string
}

variable "vpc_host_project" {
  description = "The Shared VPC host project ID"
  type        = string
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
}

variable "subnetwork_name" {
  description = "The name of the VPC subnetwork"
  type        = string
}

variable "vm_name" {
  description = "The name of the virtual machine"
  type        = string
  default     = "vllm-flex"
}

variable "machine_type" {
  description = "The Compute Engine machine type"
  type        = string
  default     = "a3-highgpu-1g"
}

variable "disk_size" {
  description = "The Compute Engine disk size"
  type        = number
  default     = 200
}

variable "disk_type" {
  description = "The Compute Engine disk type"
  type        = string
  default     = "pd-ssd"
}


variable "gpu_type" {
  description = "The GPU type to attach"
  type        = string
  default     = "nvidia-h100-80gb"
}

variable "gpu_count" {
  description = "Number of GPUs to attach (set to 0 for no GPUs)"
  type        = number
  default     = 1
}

variable "model_path" {
  description = "The GCS path to the model weights (e.g., gs://bucket/model)"
  type        = string
}

variable "sync_scripts" {
  description = "List of scripts to sync to the VM"
  type        = list(string)
  default = [
    "aiperf_benchmark.sh",
    "vllm_serve_gpu_container.sh",
    "vllm_serve_gpu.sh",
    "sglang_serve_gpu.sh",
    "llm-tui.sh",
    "lmcache.sh",
    "mooncake.sh"
  ]
}

variable "local_ssd_count" {
  description = "Number of local SSDs to attach to the VM (each is 375GB)"
  type        = number
  default     = 0
}

variable "local_ssd_interface" {
  description = "The interface for the local SSD (NVME or SCSI)"
  type        = string
  default     = "NVME"
}