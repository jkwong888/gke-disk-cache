 
# clone the script to prepare images

clone the startup script from [this git repo](https://github.com/ai-on-gke/tools/tree/main/gke-disk-image-builder).

```
curl -o packer/common/prepare_images.sh https://raw.githubusercontent.com/ai-on-gke/tools/refs/heads/main/gke-disk-image-builder/script/startup.sh 
```


# install packer

install packer.


# update your variables

you need to add a variable file to tell packer what networks to use, etc.  you can use this example.  place this in `variables.pkrvars.hcl` for example.

```
project_id = "jkwng-kueue-dev"
zone       = "us-central1-c"
network = "projects/jkwng-nonprod-vpc/global/networks/shared-vpc-nonprod-1"
subnetwork = "projects/jkwng-nonprod-vpc/regions/us-central1/subnetworks/kueue-dev"
images = [
    "vllm/vllm-v0.11.0"
]
```

# run packer

```
packer build --var-file=variables.pkrvars.hcl .
```

at the end you'll have a disk image named `image-disk-<timestamp>` with all of the container images pre-unpacked ready to be cloned to be attached to GKE nodes