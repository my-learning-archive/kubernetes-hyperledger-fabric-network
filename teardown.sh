#!/bin/bash

set -o allexport && source .env && set +o allexport




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

# orderer CA
kubectl delete -f kubernetes-manifests/base/orderers/ca-orderers.yaml

# org1 and org2 CA
kubectl delete -f kubernetes-manifests/base/org1/ca-org1.yaml
kubectl delete -f kubernetes-manifests/base/org2/ca-org2.yaml

# ca-cli
kubectl delete -f kubernetes-manifests/base/ca-cli.yaml

# cli
kubectl delete -f kubernetes-manifests/base/cli.yaml

# NFS Volumes
kubectl delete -f kubernetes-manifests/external/nfs-volumes.yaml