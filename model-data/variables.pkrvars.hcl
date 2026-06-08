project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
models     = [
    "google/gemma-3-4b-it",
]
disk_name = "model-data"
