# Hyperledger Fabric Network in Kubernetes

This repository is an experimental attempt at implementing an Hyperledger Fabric Network in Kubernetes. The end goal is to create a dynamic HLF network in Kubernetes, a spiritual successor to [this older repository, which achieves the same goal in a local environment with Docker and Docker Compose](https://github.com/my-learning-archive/hyperledger-fabric-dynamic-network).

**Requirements:**

- A Kubernetes cluster
- A NFS server


---
## Before start:

The easiest way to satisfy the requirement of a Kubernetes cluster is to setup a local Kubernetes cluster with Docker + Minikube. Once both Docker and Minikube are installed on the system / virtual machine, the following steps can be taken: 

1. Start minikube:
```bash
minikube start
```

2. Create namespace ('hlf-network') and context:
```bash
kubectl apply -f kubernetes-manifests/external/namespace.yaml
kubectl config set-context my-context --cluster='minikube' --namespace='hlf-network' --user='minikube'
kubectl config use-context my-context
```

The easiest way to satisfy the requirement of an NFS server is to have a local container running one, to do this, the following steps should be taken:

3. Enable the nfs and nfsd kernel modules, create a folder to be shared via NFS, and start a dockerized NFS server (locally):
```bash
sudo modprobe nfs && sudo modprobe nfsd
mkdir -p ./nfs-storage
docker run --name=nfs.server -itd --privileged=true --net=host -v ./nfs-storage:/nfs-storage -e NFS_EXPORT_0='/nfs-storage *(rw,no_root_squash)' erichough/nfs-server
```


---
## Quick setup:

We will start by creating a basic HLF network with one cluster-wide TLS CA; three orderers; and two organizations, with two peers each.

1. Start the base HLF Network:
```bash
./teardown.sh && ./start.sh
```