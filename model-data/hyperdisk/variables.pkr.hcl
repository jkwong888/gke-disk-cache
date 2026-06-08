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
    default = "/mnt/disks"
}

variable "models" {
    type = list(string)
}


# builder_sa = "packer@my-project.iam.gserviceaccount.com"