#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# TODO




############################################################## 
# TEARING DOWN NETWORK
##############################################################

printf "${C_BLUE_BOLD}\nteardown.sh:${C_BLUE}\n > TEARING DOWN NETWORK\n\n${C_RESET}"

# TLS CA
kubectl delete -f kubernetes-manifests/base/tls-ca.yaml

# orderers CA
kubectl delete -f kubernetes-manifests/base/orderers/ca-orderers.yaml

# org1 and org2 CA
kubectl delete -f kubernetes-manifests/base/org1/ca-org1.yaml
kubectl delete -f kubernetes-manifests/base/org2/ca-org2.yaml

# orderers
kubectl delete -f kubernetes-manifests/base/orderers/orderer0-orderers.yaml
kubectl delete -f kubernetes-manifests/base/orderers/orderer1-orderers.yaml
kubectl delete -f kubernetes-manifests/base/orderers/orderer2-orderers.yaml

# peers
kubectl delete -f kubernetes-manifests/base/org1/peer0-org1.yaml
kubectl delete -f kubernetes-manifests/base/org1/peer1-org1.yaml
kubectl delete -f kubernetes-manifests/base/org2/peer0-org2.yaml
kubectl delete -f kubernetes-manifests/base/org2/peer1-org2.yaml

# ca-cli
kubectl delete -f kubernetes-manifests/base/ca-cli.yaml

# cli
kubectl delete -f kubernetes-manifests/base/cli.yaml

# NFS Volumes
kubectl delete -f kubernetes-manifests/external/nfs-volumes.yaml