#!/bin/bash

set -o allexport && source .env && set +o allexport




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# TODO




############################################################## 
# STARTING BASE CA SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE CA SERVICES\n\n${C_RESET}"

# NFS volumes
kubectl apply -f kubernetes-manifests/external/nfs-volumes.yaml

# TLS CA
kubectl apply -f kubernetes-manifests/base/tls-ca.yaml 

# orderer CA
kubectl apply -f kubernetes-manifests/base/orderers/ca-orderer.yaml

# org1 and org2 CA
kubectl apply -f kubernetes-manifests/base/org1/ca-org1.yaml
kubectl apply -f kubernetes-manifests/base/org2/ca-org2.yaml

# ca-cli
kubectl apply -f kubernetes-manifests/base/ca-cli.yaml

# cli
kubectl apply -f kubernetes-manifests/base/cli.yaml

# wait for all containers to start
while kubectl get pods | grep 'ContainerCreating'; do
    sleep 10
done

# are all services are running?
kubectl get pods | awk '{print $3}' | tail -n +2 | awk '!seen[$0]++ && NR>1{exit 1}'
[[ ! $? -eq 0 ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more containers did not start. Exiting. ${C_RESET}"
    exit 1
} 




############################################################## 
# GENERATING CRYPTO-MATERIALS - BASE ORGS
##############################################################

for ORG_NAME in "org1" "org2"; do
    
    printf "${C_BLUE_BOLD}\ngenerate.sh:${C_BLUE}\n > GENERATING CRYPTO-MATERIALS - ${ORG_NAME}\n\n${C_RESET}"

    ORG_CA_HOSTNAME=ca-${ORG_NAME}
    ORG_CA_ADMIN_USERNAME=admin
    ORG_CA_ADMIN_PASSWORD=adminpw
    TLS_CA_HOSTNAME=tls-ca
    TLS_CA_ADMIN_USERNAME=tls-admin
    TLS_CA_ADMIN_PASSWORD=tls-adminpw

    . create-crypto.sh ${ORG_NAME} ${ORG_CA_HOSTNAME} ${ORG_CA_ADMIN_USERNAME} ${ORG_CA_ADMIN_PASSWORD} ${TLS_CA_HOSTNAME} ${TLS_CA_ADMIN_USERNAME} ${TLS_CA_ADMIN_PASSWORD}
    createOrg

done




############################################################## 
# CREATING BASE APPLICATION CHANNEL 
##############################################################

# TODO


############################################################## 
# JOINING BASE PEERS TO APPLICATION CHANNEL 
##############################################################

# TODO



############################################################## 
# CONFIGURING BASE ANCHOR PEERS
##############################################################

# TODO


############################################################## 
# CONFIGURING DISCOVERY SERVICES
##############################################################

# TODO


