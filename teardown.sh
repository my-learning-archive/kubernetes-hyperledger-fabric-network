#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# TEARING DOWN - KUBERNETES NETWORK
##############################################################

printf "${C_BLUE_BOLD}\nteardown.sh:${C_BLUE}\n > TEARING DOWN - KUBERNETES NETWORK\n\n${C_RESET}"

# TLS CA
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/tls-ca.yaml

# organizational CAs
for DEPLOYMENT_NAME in $(kubectl get deploy | awk '{print $1}' | grep '^ca' | grep -v 'cli'); do
    kubectl delete deploy ${DEPLOYMENT_NAME}
done
for SERVICE_NAME in $(kubectl get service | awk '{print $1}' | grep '^ca' | grep -v 'cli'); do
    kubectl delete service ${SERVICE_NAME}
done

# orderers
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer0-orderers.yaml
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer1-orderers.yaml
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer2-orderers.yaml

# peers
for DEPLOYMENT_NAME in $(kubectl get deploy | awk '{print $1}' | grep 'peer'); do
    kubectl delete deploy ${DEPLOYMENT_NAME}
done
for SERVICE_NAME in $(kubectl get service | awk '{print $1}' | grep 'peer'); do
    kubectl delete service ${SERVICE_NAME}
done

# external chaincodes
for DEPLOYMENT_NAME in $(kubectl get deploy | awk '{print $1}' | grep 'chaincode'); do
    kubectl delete deploy ${DEPLOYMENT_NAME}
done
for SERVICE_NAME in $(kubectl get service | awk '{print $1}' | grep 'chaincode'); do
    kubectl delete service ${SERVICE_NAME}
done

# ca-cli
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/ca-cli.yaml

# cli
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/cli.yaml

# configuration files - ConfigMaps
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/builders-config.yaml
kubectl delete -f ${SCRIPT}/kubernetes-manifests/base/configtx.yaml

# NFS Volumes
kubectl delete -f ${SCRIPT}/kubernetes-manifests/external/nfs-volumes.yaml

kubectl wait --for=delete pods --all --timeout=600s




############################################################## 
# TEARING DOWN - LOCAL DIRECTORIES
##############################################################

printf "${C_BLUE_BOLD}\nteardown.sh:${C_BLUE}\n > TEARING DOWN - LOCAL DIRECTORIES\n\n${C_RESET}"

rm -rvf ${SCRIPT}/kubernetes-manifests/expand/*