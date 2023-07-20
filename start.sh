#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CLI_ENDPOINT=${ENV_KUBERNETES_CLI_ENDPOINT}
BASE_CHANNEL_NAME=${ENV_BASE_CHANNEL_NAME} 
SYS_CHANNEL_NAME=${ENV_SYS_CHANNEL_NAME}

TLS_CA_HOSTNAME=tls-ca
TLS_CA_ADMIN_USERNAME=tls-admin
TLS_CA_ADMIN_PASSWORD=tls-adminpw




############################################################## 
# STARTING BASE CA SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE CA SERVICES\n\n${C_RESET}"

# NFS volumes
kubectl apply -f kubernetes-manifests/external/nfs-volumes.yaml

# TLS CA
kubectl apply -f kubernetes-manifests/base/tls-ca.yaml 

# orderer CA
kubectl apply -f kubernetes-manifests/base/orderers/ca-orderers.yaml

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

    printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING CRYPTO-MATERIALS - ${ORG_NAME}\n\n${C_RESET}"
    
    ORG_CA_HOSTNAME=ca-${ORG_NAME}
    ORG_CA_ADMIN_USERNAME=admin
    ORG_CA_ADMIN_PASSWORD=adminpw

    . create-crypto.sh ${ORG_NAME} ${ORG_CA_HOSTNAME} ${ORG_CA_ADMIN_USERNAME} ${ORG_CA_ADMIN_PASSWORD} ${TLS_CA_HOSTNAME} ${TLS_CA_ADMIN_USERNAME} ${TLS_CA_ADMIN_PASSWORD}
    createOrg
    createEntity "peer0" "${ORG_NAME}peer0" "${ORG_NAME}peer0pw"
    createEntityTLS "peer0" "${ORG_NAME}peer0" "${ORG_NAME}peer0pw"
    createEntity "peer1" "peer1" "${ORG_NAME}peer1pw"
    createEntityTLS "peer1" "${ORG_NAME}peer1" "${ORG_NAME}peer1pw"

done




############################################################## 
# GENERATING CRYPTO-MATERIALS - ORDERERS
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING CRYPTO-MATERIALS - orderers\n\n${C_RESET}"

ORG_CA_HOSTNAME=ca-orderers
ORG_CA_ADMIN_USERNAME=admin
ORG_CA_ADMIN_PASSWORD=adminpw

. create-crypto.sh orderers ${ORG_CA_HOSTNAME} ${ORG_CA_ADMIN_USERNAME} ${ORG_CA_ADMIN_PASSWORD} ${TLS_CA_HOSTNAME} ${TLS_CA_ADMIN_USERNAME} ${TLS_CA_ADMIN_PASSWORD}
createOrg
createEntity "orderer0" "orderer0" "orderer0pw"
createEntityTLS "orderer0" "orderer0" "orderer0pw"
createEntity "orderer1" "orderer1" "orderer1pw"
createEntityTLS "orderer1" "orderer1" "orderer1pw"
createEntity "orderer2" "orderer2" "orderer2pw"
createEntityTLS "orderer2" "orderer2" "orderer2pw"




############################################################## 
# GENERATING GENESIS BLOCK 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING GENESIS BLOCK\n\n${C_RESET}"

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_ENDPOINT}-* | awk '{print $1}')

kubectl cp ${SCRIPT}/configtx.yaml ${KUBERNETES_CLI_POD_NAME}:/etc/hyperledger/configtx/configtx.yaml

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
configtxgen \
    -configPath /etc/hyperledger/configtx/ \
    -profile TwoOrgOrdererGenesis \
    -channelID '${SYS_CHANNEL_NAME}' \
    -outputBlock /etc/hyperledger/configtx/genesis.block
'




############################################################## 
# GENERATING BASE APPLICATION CHANNEL CREATION TRANSACTION 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING APPLICATION CHANNEL CREATION TRANSACTION - ${BASE_CHANNEL_NAME}\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
configtxgen \
    -configPath /etc/hyperledger/configtx/ \
    -profile TwoOrgChannel \
    -channelID '${SYS_CHANNEL_NAME}' \
    -outputCreateChannelTx /etc/hyperledger/configtx/'${BASE_CHANNEL_NAME}'.tx
'




############################################################## 
# GENERATING BASE ANCHOR PEER TRANSACTIONS 
##############################################################

for ORG_NAME in "org1" "org2"; do

    printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING ANCHOR PEER UPDATE TRANSACTION - ${ORG_NAME}\n\n${C_RESET}"

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
configtxgen \
    -configPath /etc/hyperledger/configtx/ \
    -profile TwoOrgChannel \
    -channelID '${SYS_CHANNEL_NAME}' \
    -asOrg '${ORG_NAME^}'MSP \
    -outputAnchorPeersUpdate /etc/hyperledger/configtx/'${ORG_NAME^}'MSPanchors.tx
    '
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


