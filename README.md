# Hyperledger Fabric Network in Kubernetes

This repository is an experimental attempt at implementing an Hyperledger Fabric Network in Kubernetes. The end goal is to create a dynamic HLF network in Kubernetes, a spiritual successor to [this older repository, which achieves the same goal in a local environment with Docker and Docker Compose](https://github.com/my-learning-archive/hyperledger-fabric-dynamic-network).

**Requirements:**

- A Kubernetes cluster
- A NFS server


---
## Before start:

The easiest way to satisfy the requirement of a Kubernetes cluster is to setup a local Kubernetes cluster with Docker (v24.0.4) + Minikube (v1.30.1). Once both Docker and Minikube are installed on the system / virtual machine, the following steps can be taken: 

1. Start minikube with three nodes:
```bash
minikube start -n 3
```

2. Create namespace ('hlf-network') and context:
```bash
kubectl apply -f kubernetes-manifests/external/namespace.yaml
kubectl config set-context my-context --cluster='minikube' --namespace='hlf-network' --user='minikube'
kubectl config use-context my-context
```

The easiest way to satisfy the requirement of an NFS server is to have a local container running one, to do this, the following steps should be taken:

3. Enable the nfs and nfsd kernel modules:
```bash
sudo modprobe nfs && sudo modprobe nfsd
```

4. Create a folder to be shared via NFS, and start a dockerized NFS server (locally)
```bash
mkdir -p ./nfs-storage
docker run --name=nfs.server -itd --privileged=true --net=host -v ./nfs-storage:/nfs-storage -e NFS_EXPORT_0='/nfs-storage *(rw,no_root_squash)' erichough/nfs-server
```

Since we are going to test the network using a version of the *marbles* chaincode, suitable for external chaincode building:

5. Build the *marbles* chaincode docker image inside the Kubernetes cluster:
```bash
minikube image build --all -t chaincode-marbles ./chaincodes/marbles/
```

---
## Setup:

This is a guide on how to use each script to generate/manage a dynamic HLF network.

### **How to create a basic Hyperledger Fabric network:**

A basic HLF network can be created simply by running the `start.sh` script. This network is characterized by one cluster-wide TLS CA; three orderers; and two organizations, each with one organizational CA and two peers. To ensure this is executed in a clean environment, the execution of `start.sh` is preceeded with the execution of `teardown.sh`.

```bash
./teardown.sh && ./start.sh
```

### **How to create Hyperledger Fabric users:**

An HLF user can be created with the `create-user.sh` script. A user is created in the context of an HLF organization, so this must be specified, along with the credentials required to access both the organizational CA and the TLS CA. In this implementation, an optional custom attribure - a "role" - can be given to the created user. In the following snippet, two users are created, one for *org1* with a *WRITER* role, and another for *org2* with a *READER* role. For more information, execute `./create-user.sh --help`.

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

### **How to create Hyperledger Fabric application channels:**

An HLF application channel can be created with the `create-channel.sh` script. The list of HLF organizations that will make up the initiial membership of the application channel must be provided. For more information, execute `./create-channel.sh --help`.

```bash
./create-channel.sh \
 --channel-name new-channel \
 --orgs-list org1,org2
```

### **How to deploy Hyperledger Fabric chaincodes:**

An HLF chaincode can be deployed to an application channel with the `deploy-chaincode.sh` script. In Kubernetes, pods cannot create other pods within the cluster (and rightfully so, as that would be a severe security violatio), so chaincode is not installed directly in the peers, but in separate pods that are created ad-hoc - to do this, the image containing the code of the chaincode must be available within the Kubernetes cluster, and is specified with the `--chaincode-image` flag. For more information, execute `./deploy-chaincode.sh --help`.

```bash
./deploy-chaincode.sh \
 --chaincode-image chaincode-marbles \
 --chaincode-label marbles \
 --channel-name base-channel \
 --channel-org-name org1
```

### **How to create Hyperledger Fabric organizations:**

An HLF organization can be created with the `create-org.sh` script. Optionally, the `--channel-name` and `--channel-org-name` flags specify that this newly created organization should be added to an application channel. For this end, internally, the `create.org.sh` script calls the `join-org-to-channel.sh` script (as described in the next section). For more information, execute `./create-org.sh --help`.

```bash
./create-org.sh \
 --org-name org3 \
 --org-ca-admin-username admin \
 --org-ca-admin-password adminpw \
 --tls-ca-admin-username tls-admin \
 --tls-ca-admin-password tls-adminpw \
 --channel-name base-channel \
 --channel-org-name org1
```

### **How to join existing Hyperledger Fabric organizations to existing application channels:**

An existing HLF organization can be joined to an existing application channel with the `join-org-to-channel.sh` script. If the channel contains a previously committed chaincode, it will not be accessible to the newly joined organization right away, and must be redeployed - this will automatically increase its version number - for the newly joined organization to participate in its execution. In this scenario, the peers of the newly joined organization will replicate the world state of the previous version of the chaincode. For more information, execute `./join-org-to-channel.sh --help`.

```bash
./join-org-to-channel.sh \
 --org-name org3 \
 --channel-name new-channel \
 --channel-org-name org1
```

### **How to create Hyperledger Fabric peers:**

A HLF peer can be created with the `create-peer.sh` script. This script joins the newly created peer to all application channels its organization belongs to, and installs the resident chaincodes. Therefore, the newly created peer is immediately apt to participate in the execution of the chaincodes its organization has access to. FOr more information, execute `./create-peer.sh --help`. For convention, the newly created peer is not named, but numbered, according to the logic sequence - in the following case, considering *org1* already has *peer0-org1* and *peer1-org2*, the hostname of the newly created peer will be, automatically, *peer2-org1*.

```bash
./create-peer.sh \
 --org-name org1 \
 --org-ca-admin-username admin \
 --org-ca-admin-password adminpw \
 --tls-ca-admin-username tls-admin \
 --tls-ca-admin-password tls-adminpw
```

### **Quick start:**

Lastly, all of the above commands are concatenated in a single command, for convenience:

```bash
./teardown.sh && ./start.sh && \

./create-user.sh --org-name org1 --user-type client --user-hostname host.minikube.internal --user-username user1-org1 --user-password user1-org1-pw --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw --user-role WRITER && \

./create-user.sh --org-name org2 --user-type client --user-hostname host.minikube.internal --user-username user1-org2 --user-password user1-org2-pw --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw --user-role READER && \

./create-channel.sh --channel-name new-channel --orgs-list org1,org2 && \

./deploy-chaincode.sh --chaincode-image chaincode-marbles --chaincode-label marbles --channel-name base-channel --channel-org-name org1 && \

./create-org.sh --org-name org3 --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw --channel-name base-channel --channel-org-name org1 && \

./join-org-to-channel.sh --org-name org3 --channel-name new-channel --channel-org-name org1 && \

./create-peer.sh --org-name org1 --org-ca-admin-username admin --org-ca-admin-password adminpw --tls-ca-admin-username tls-admin --tls-ca-admin-password tls-adminpw
```

---
## Testing:

There are myriads of ways to test HLF networks via the deployed chaincodes. In the previously described set up, the easiest way is to execute a shell in the *fabric-tools* cli pod, and to invoke a deployed chaincode. As a result of the previous sequence of script executions, we can, for instance, invoke the *marbles* chaincode, with participation of *peer0*, *peer1* and *peer2* of *org1*, and *peer0* and *peer1* of *org2*:

```bash
# log inside cli pod:
kubectl exec -it $(kubectl get pods | awk '{print $1}' | grep ^cli) -- bash

# test the marbles chaincode:
peer chaincode invoke --channelID base-channel --name marbles -o orderer0-orderers:7050 --peerAddresses peer0-org1:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1/peers/peer0-org1/tls/ca.crt --peerAddresses peer1-org1:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1/peers/peer1-org1/tls/ca.crt --peerAddresses peer2-org1:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1/peers/peer2-org1/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2/peers/peer0-org2/tls/ca.crt --peerAddresses peer1-org2:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2/peers/peer1-org2/tls/ca.crt --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/ca.crt -c '{"Args":["initMarble","marble1","blue","35","tom"]}' --waitForEvent
```

---
## TODO:
- Gateway peers exposed to the outside via k8s' NodePort - this is not secure - use ingress instead.
- deploy-chaincode.sh: Find cloud native alternative to pass collection-config onto the k8s cluster.
- Migrate what should be implemented as k8s *Secrets* to that format.
- ~~Collection profiles are still unsupported in deploy-chaincode.sh~~ Chaincode deployment with collections-config files is not cloud native, because said collection-config files need to exist locally... Find a way to fix this.
- ~~Right now, because of the service and directory conventions, there can't be two chaincodes with different names in the same channel, fix this...~~
- ~~./create-org.sh - new orgs joining channel stilll can't use chaincode (... has not yet been approved by this org)~~ After an org is added to the channel, it is required to run the deploy-chaincode.sh script again, for the same chaincode, but with increased version number.
- ~~error checking after every single kubectl exec command.~~
