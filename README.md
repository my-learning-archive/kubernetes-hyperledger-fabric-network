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
## Setup:

We will start by creating a basic HLF network with one cluster-wide TLS CA; three orderers; and two organizations, with two peers each.

1. Start the base HLF Network:
```bash
./teardown.sh && ./start.sh
```

2. Create a few Hyperledger Fabric users - for instance, *user1-org1* belonging to *org1*, with *WRITER* role; and *user1-org2* belonging to *org2*, with *READER* role:
```bash
./create-user.sh \
 --org-name org1 \
 --user-type client \
 --user-hostname host.minikube.internal \
 --user-username user1-org1 \
 --user-password user1-org1-pw \
 --org-ca-admin-username admin \
 --org-ca-admin-password adminpw \
 --tls-ca-admin-username tls-admin \
 --tls-ca-admin-password tls-adminpw \
 --user-role WRITER

./create-user.sh \
 --org-name org2 \
 --user-type client \
 --user-hostname host.minikube.internal \
 --user-username user1-org2 \
 --user-password user1-org2-pw \
 --org-ca-admin-username admin \
 --org-ca-admin-password adminpw \
 --tls-ca-admin-username tls-admin \
 --tls-ca-admin-password tls-adminpw \
 --user-role READER   
```

3. Deploy a chaincode:
```bash
./deploy-chaincode.sh \
 --chaincode-relative-name fabcar \
 --chaincode-label chaincode \
 --chaincode-version 1 \
 --chaincode-language golang \
 --channel-name allarewelcome \
 --channel-org-name org1 \
 --signature-policy "OR('Org1MSP.member','Org2MSP.member')"
```


--- 
## Quick setup:
```bash
./teardown.sh && ./start.sh && ./create-user.sh --org-name org1 --user-type client --user-hostname host.minikube.internal --user-username user1-org1 --user-password user1-org1-pw --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw --user-role WRITER && ./create-user.sh --org-name org2 --user-type client --user-hostname host.minikube.internal --user-username user1-org2 --user-password user1-org2-pw --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw --user-role READER   
```
