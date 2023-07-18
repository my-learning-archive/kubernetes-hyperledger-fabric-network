# Hyperledger Fabric Network in Kubernetes

This repository is an experimental attempt at implementing an Hyperledger Fabric Network in Kubernetes. The end goal is to create a dynamic HLF network in Kubernetes.

## Basic steps:

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

3. Create a folder to be shared via NFS, and start an NFS server (locally):
```bash
mkdir ./nfs-storage
docker run --name=nfs.server -itd --privileged=true --net=host -v ./nfs-storage:/nfs-storage -e NFS_EXPORT_0='/nfs-storage *(rw,no_root_squash)' erichough/nfs-server
```

## References:

- NFS in Kubernetes: \
https://matthewpalmer.net/kubernetes-app-developer/articles/kubernetes-volumes-example-nfs-persistent-volume.html