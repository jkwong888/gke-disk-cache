# Create packer disk image with model data

Create a disk image containing the cached models from huggingface.

the model disk can be used as a secondary boot disk in the GKE node pool or in the compute class definition when creating auto provisioned node pools.

# install packer

install packer.

# create the secret 

create a secret manager called `hf_token` containing your huggingface token.  make sure the SA running packer has access to this secret.

# update your variables

you need to add a variable file to tell packer what networks to use, etc.  you can use this example, you can place it in `variables.pkvars.hcl`

```
project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
models   = ["google/gemma-3-4b-it"]
disk_name = "model-data"
```

# run packer

```
packer build --var-file=variables.pkrvars.hcl .
```


at the end you'll have a disk image named `model-data-<timestamp>` with all of the downloaded models from huggingface stored in models/<model-id>