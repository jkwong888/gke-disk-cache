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
    default = "image-disk"
}

variable "images" {
    type = list(string)
    default = [
        "vllm/vllm-openai:v0.11.0"
    ]
}

# builder_sa = "packer@my-project.iam.gserviceaccount.com"