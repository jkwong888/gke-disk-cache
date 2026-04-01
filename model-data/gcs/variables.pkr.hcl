# Below variables are set with example values. Please adjust them accordingly.
variable "project_id" {
    type = string
}

variable "zone" {
    type = string
}

variable "network" {}
variable "subnetwork" {}

# variable "builder_sa" {
#   type = string
# }

variable "disk_name" {
    type = string
    default = "model-data"
}

variable "mount_path" {
    type = string
    default = "/tmp"
}

variable "models" {
    type = list(string)
}

variable "gcs_bucket" {
    type = string
}

variable "gcs_prefix" {
    type = string
}


# builder_sa = "packer@my-project.iam.gserviceaccount.com"