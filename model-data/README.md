# Model data cache

Cache models from huggingface.

- [hyperdisk/](hyperdisk/) - build a hyperdisk that can be mounted from multiple nodes in the GKE node pool. if the models do not change often, we can use this model disk to speed up loading models from an attached disk instead of pulling it off of GCS. 
- [gcs/](gcs/) - use a VM to download models off of huggingface and write it to a gcs bucket. we can use zonal anywhere cache and gcsfuse to speed up reads off of GCS, esp if models change often.

## Prerequisites

install packer.

---

## Hyperdisk

### Create the secret 

create a secret manager called `hf_token` containing your huggingface token. make sure the SA running packer has access to this secret.

### Update your variables

you need to add a variable file to tell packer what networks to use, etc. you can use this example, you can place it in `hyperdisk/variables.pkrvars.hcl`

```hcl
project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
models   = ["google/gemma-3-4b-it"]
disk_name = "model-data"
```

### Run packer

```bash
cd hyperdisk
packer build --var-file=variables.pkrvars.hcl .
```

at the end you'll have a disk image named `model-data-<timestamp>` with all of the downloaded models from huggingface stored in models/<model-id>

---

## GCS

The GCS method uses a wrapper script to automatically calculate the required disk size and upload the models directly to your Google Cloud Storage bucket.

### Set your token

export your Hugging Face token as an environment variable:
```bash
export HF_TOKEN="your_hf_token"
```

### Update your variables

you need to add a variable file to tell packer what networks and bucket to use. you can use this example, you can place it in `gcs/variables.pkrvars.hcl`

```hcl
project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
network_project_id = "jkwng-nonprod-vpc"
models   = ["google/gemma-3-4b-it"]
gcs_bucket = "my-model-bucket"
gcs_prefix = "models"
```

### Run the download script

Run the automated script instead of standard packer:
```bash
cd gcs
./run_packer_download.sh
```

the script will calculate the needed disk size for your models, provision a temporary VM using packer, download the models from huggingface, and upload them to `gs://<gcs_bucket>/<gcs_prefix>/<model-id>`.
