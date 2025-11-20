project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
images = [
    "docker.io/vllm/vllm-openai:v0.11.0"
]