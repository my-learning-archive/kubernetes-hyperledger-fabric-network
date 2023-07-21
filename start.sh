#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CLI_ENDPOINT=${ENV_KUBERNETES_CLI_ENDPOINT}
KUBERNETES_ORDERER_ENDPOINT=${ENV_KUBERNETES_ORDERER_ENDPOINT}
BASE_CHANNEL_NAME=${ENV_BASE_CHANNEL_NAME} 
SYS_CHANNEL_NAME=${ENV_SYS_CHANNEL_NAME}

TLS_CA_HOSTNAME=tls-ca
TLS_CA_ADMIN_USERNAME=tls-admin
TLS_CA_ADMIN_PASSWORD=tls-adminpw

CLI_INTERNAL_CRYPTO_CONFIG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/
CLI_INTERNAL_CONFIGTX_PATH=/etc/hyperledger/configtx/




############################################################## 
# STARTING BASE CA SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE CA SERVICES\n\n${C_RESET}"

# NFS volumes
kubectl apply -f kubernetes-manifests/external/nfs-volumes.yaml

# TLS CA
kubectl apply -f kubernetes-manifests/base/tls-ca.yaml 

# orderers CA
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
    createEntity "peer0" "peer0-${ORG_NAME}-un" "peer0-${ORG_NAME}-pw"
    createEntityTLS "peer0" "peer0-${ORG_NAME}-un" "peer0-${ORG_NAME}-pw"
    createEntity "peer1" "peer1-${ORG_NAME}-un" "peer1-${ORG_NAME}-pw"
    createEntityTLS "peer1" "peer1-${ORG_NAME}-un" "peer1-${ORG_NAME}-pw"

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
createEntity "orderer0" "orderer0-orderers-un" "orderer0-orderers-pw"
createEntityTLS "orderer0" "orderer0-orderers-un" "orderer0-orderers-pw"
createEntity "orderer1" "orderer1-orderers-un" "orderer1-orderers-pw"
createEntityTLS "orderer1" "orderer1-orderers-un" "orderer1-orderers-pw"
createEntity "orderer2" "orderer2-orderers-un" "orderer2-orderers-pw"
createEntityTLS "orderer2" "orderer2-orderers-un" "orderer2-orderers-pw"




############################################################## 
# GENERATING GENESIS BLOCK 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING GENESIS BLOCK\n\n${C_RESET}"

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_ENDPOINT}-* | awk '{print $1}')

kubectl cp ${SCRIPT}/configtx.yaml ${KUBERNETES_CLI_POD_NAME}:${CLI_INTERNAL_CONFIGTX_PATH}/configtx.yaml

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath '${CLI_INTERNAL_CONFIGTX_PATH}'/ \
    -profile TwoOrgOrdererGenesis \
    -channelID '${SYS_CHANNEL_NAME}' \
    -outputBlock '${CLI_INTERNAL_CONFIGTX_PATH}'/genesis.block

###################### INTERNAL COMMAND ######################'




############################################################## 
# GENERATING BASE APPLICATION CHANNEL CREATION TRANSACTION 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING APPLICATION CHANNEL CREATION TRANSACTION - ${BASE_CHANNEL_NAME}\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath '${CLI_INTERNAL_CONFIGTX_PATH}'/ \
    -profile TwoOrgChannel \
    -channelID '${BASE_CHANNEL_NAME}' \
    -outputCreateChannelTx '${CLI_INTERNAL_CONFIGTX_PATH}'/'${BASE_CHANNEL_NAME}'.tx

###################### INTERNAL COMMAND ######################'




############################################################## 
# GENERATING BASE ANCHOR PEER TRANSACTIONS 
##############################################################

for ORG_NAME in "org1" "org2"; do

    printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING ANCHOR PEER UPDATE TRANSACTION - ${ORG_NAME}\n\n${C_RESET}"

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath '${CLI_INTERNAL_CONFIGTX_PATH}'/ \
    -profile TwoOrgChannel \
    -channelID '${BASE_CHANNEL_NAME}' \
    -asOrg '${ORG_NAME^}'MSP \
    -outputAnchorPeersUpdate '${CLI_INTERNAL_CONFIGTX_PATH}'/'${ORG_NAME^}'MSPanchors.tx

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# STARTING BASE PEER SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE PEER SERVICES\n\n${C_RESET}"

# orderers
kubectl apply -f kubernetes-manifests/base/orderers/orderer0-orderers.yaml
kubectl apply -f kubernetes-manifests/base/orderers/orderer1-orderers.yaml
kubectl apply -f kubernetes-manifests/base/orderers/orderer2-orderers.yaml

# peers
kubectl apply -f kubernetes-manifests/base/org1/peer0-org1.yaml
kubectl apply -f kubernetes-manifests/base/org1/peer1-org1.yaml
kubectl apply -f kubernetes-manifests/base/org2/peer0-org2.yaml
kubectl apply -f kubernetes-manifests/base/org2/peer1-org2.yaml

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
# CREATING BASE APPLICATION CHANNEL 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > CREATING APPLICATION CHANNEL - ${BASE_CHANNEL_NAME}\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

peer channel create \
    -o '${KUBERNETES_ORDERER_ENDPOINT}:7050' \
    -c '${BASE_CHANNEL_NAME}' \
    -f '${CLI_INTERNAL_CONFIGTX_PATH}'/'${BASE_CHANNEL_NAME}'.tx \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################'




############################################################## 
# JOINING BASE PEERS TO APPLICATION CHANNEL 
##############################################################


for ORG_NAME in "org1" "org2"; do

	printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > JOINING PEERS TO APPLICATION CHANNEL - ${ORG_NAME}\n\n${C_RESET}"

	PEERS_LIST=$(kubectl get service | awk '{print $1}' | grep ^peer | grep ${ORG_NAME})

	for PEER_HOSTNAME in ${PEERS_LIST}; do
        
        echo -e "${C_BLUE}\nJoining ${PEER_HOSTNAME} ...${C_RESET}"

        kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
export CORE_PEER_ADDRESS='${PEER_HOSTNAME}':7051
export CORE_PEER_MSPCONFIGPATH='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt

peer channel fetch oldest '${BASE_CHANNEL_NAME}'.block \
    -o '${KUBERNETES_ORDERER_ENDPOINT}:7050' \
    -c '${BASE_CHANNEL_NAME}' \
    --tls --cafile ${ORDERER_TLS_CA}

peer channel join \
    -b '${BASE_CHANNEL_NAME}'.block

###################### INTERNAL COMMAND ######################'

    done
done




############################################################## 
# CONFIGURING BASE ANCHOR PEERS
##############################################################

for ORG_NAME in "org1" "org2"; do

	printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > CONFIGURING ANCHOR PEER - ${ORG_NAME}\n\n${C_RESET}"

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
export CORE_PEER_ADDRESS=peer0-'${ORG_NAME}':7051
export CORE_PEER_MSPCONFIGPATH='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE='${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/ca.crt

peer channel update \
    -o '${KUBERNETES_ORDERER_ENDPOINT}':7050 \
    -c '${BASE_CHANNEL_NAME}' \
    -f '${CLI_INTERNAL_CONFIGTX_PATH}'/'${ORG_NAME^}'MSPanchors.tx \
    --tls --cafile ${ORDERER_TLS_CA}  

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# CONFIGURING DISCOVERY SERVICES
##############################################################

for ORG_NAME in "org1" "org2"; do

	printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > CONFIGURING DISCOVERY SERVICE - ${ORG_NAME}\n\n${C_RESET}"

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

discover \
    --configFile '${CLI_INTERNAL_CONFIGTX_PATH}'/discovery-conf-'${ORG_NAME}'.yaml \
    --tlsCert ${CORE_PEER_TLS_CERT_FILE} \
    --tlsKey ${CORE_PEER_TLS_KEY_FILE} \
    --peerTLSCA ${CORE_PEER_TLS_ROOTCERT_FILE} \
    --userKey $(ls '${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/keystore/* | head -n 1) \
    --userCert '${CLI_INTERNAL_CRYPTO_CONFIG_PATH}'/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/signcerts/cert.pem \
    --MSP '${ORG_NAME^}'MSP \
    saveConfig

###################### INTERNAL COMMAND ######################'

done