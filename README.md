# Deploying Gemma 3 with vLLM on GKE using Secondary Boot Disks

This directory contains the Kubernetes configuration files to deploy the `google/gemma-3-4b-it` model on Google Kubernetes Engine (GKE) using the vLLM engine. This setup leverages secondary boot disks to efficiently manage and serve the model data to the vLLM pods.

## GKE requirements

We use GKE Standard with [Node Autoprovisioning](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/node-auto-provisioning) to automatically provision nodepools.  

We defined [Custom Compute Classes](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-custom-compute-classes) to have control over the types of nodepools that get created, and attach our secondary disks to be provisioned with the node

We use [secondary boot disks](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/data-container-image-preloading) to pre-load container images and model data on the nodes for faster startup.  

Note that we depend on [Kubernetes Host Path volumes](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath) here which don't work in GKE Autopilot because of security constraints, this allows us to load the model directly from the cloned secondary boot disk.  TODO is to figure out a way to do this without hostpath volumes.

Note the above combined with [Fast Starting nodes](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/fast-starting-nodes) on GKE (whenever they decide to support that in GKE Standard), you can get a pretty fast inference system on GKE :)  assuming your workload fits in a single L4.

## vLLM

We preloaded [vLLM](https://github.com/vllm-project/vllm) container image on the image disk.  This is [~12GB](https://hub.docker.com/layers/vllm/vllm-openai/v0.11.0/images/sha256-d8d39b59e909d2378ac4feeb191f7e7b6f1342477dc66b7c47cec89e9985ad8a) on docker hub, so we actually skip pulling the entire container image since we've pre-cached the layers.

vLLM has some startup processes of loading models into GPU memory and building CUDA graphs before starting the inference server.  This can be shortcut (at the expense of some performance optimizations later) by adding `--enforce-eager` argument [see docs](https://docs.vllm.ai/en/v0.7.3/serving/engine_args.html) to disable CUDA graph compilation on startup.  Alternatively we can  reduce the number of sequence lenghts it calculates the graph for, or we can pre-compute the graph and cache it on a small Filestore share for usage later which saves about a minute on startup.

## Gemma 3 4B

We pre-download [Gemma 3 4B](https://huggingface.co/google/gemma-3-4b-it) off of huggingface onto the data disk and mount it to the pod so it doesn't have to pull it off on startup or from object storage, which saves some startup time as well.  Note this model is ~8GB.


## Files

- [image-disk/](./image-disk/): packer script to prepare the container image cache disk
- [data-diskk/](./data-disk/): packer script to prepare a disk containing pre-downloaded models from Huggingface
- [gke/gemma3-deployment.yaml](./gke/gemma3-deployment.yaml): This file defines the Kubernetes `Deployment` for the vLLM server. It specifies the container image, resource requests, and mounts the secondary boot disk containing the model data.
- [gke/computeclass-inference-gemma3.yaml](./gke/computeclass-inference-gemma3.yaml): This file defines a GKE `ComputeClass` named `gemma3-inf-nodes`. This custom resource configures the node pools to be used for the inference workloads, including the machine types, GPU configurations, and the secondary boot disks that should be attached to the nodes.
- [gke/gcpresourceallowlist-model-data.yaml](./gke/gcpresourceallowlist-model-data.yaml): This file defines a `GCPResourceAllowlist`. This is a security feature that explicitly allows the GKE cluster to use specific GCP resources, in this case, the GCE disk images for the secondary boot disks.

