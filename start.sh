#!/bin/bash

set -o allexport && source .env && set +o allexport




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# TODO

############################################################## 
# STARTING BASE SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE SERVICES\n\n${C_RESET}"

# NFS volumes
kubectl apply -f kubernetes-manifests/external/nfs-volumes.yaml

# TLS CA
kubectl apply -f kubernetes-manifests/base/tls-ca.yaml 

# cli
kubectl apply -f kubernetes-manifests/base/cli.yaml 



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


