#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}
KUBERNETES_TLS_CA_HOSTNAME=${ENV_KUBERNETES_TLS_CA_HOSTNAME}
BASE_CHANNEL_NAME=${ENV_BASE_CHANNEL_NAME}

TLS_CA_ADMIN_USERNAME=tls-admin
TLS_CA_ADMIN_PASSWORD=tls-adminpw




############################################################## 
# STARTING BASE CA SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE CA SERVICES\n\n${C_RESET}"

# NFS volumes
kubectl apply -f ${SCRIPT}/kubernetes-manifests/external/nfs-volumes.yaml

# configuration files - ConfigMaps
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/configtx.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/builders-config.yaml

# TLS CA
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/tls-ca.yaml 

# orderers CA
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/orderers/ca-orderers.yaml

# org1 and org2 CA
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org1/ca-org1.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org2/ca-org2.yaml

# ca-cli
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/ca-cli.yaml

# cli
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/cli.yaml

# wait for all containers to start
while kubectl get pods | grep 'ContainerCreating'; do
    sleep 10
done
sleep 10

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
    
    KUBERNETES_ORG_CA_HOSTNAME=ca-${ORG_NAME}
    ORG_CA_ADMIN_USERNAME=admin
    ORG_CA_ADMIN_PASSWORD=adminpw

    source create-crypto.sh \
        --org-name ${ORG_NAME} \
        --org-ca-hostname ${KUBERNETES_ORG_CA_HOSTNAME} \
        --org-ca-admin-username ${ORG_CA_ADMIN_USERNAME} \
        --org-ca-admin-password ${ORG_CA_ADMIN_PASSWORD} \
        --tls-ca-hostname ${KUBERNETES_TLS_CA_HOSTNAME} \
        --tls-ca-admin-username ${TLS_CA_ADMIN_USERNAME} \
        --tls-ca-admin-password ${TLS_CA_ADMIN_PASSWORD}

    createOrg
    
    createEntity \
        --entity-name peer0 \
        --entity-username peer0-${ORG_NAME}-un \
        --entity-password peer0-${ORG_NAME}-pw
    
    createEntityTLS \
        --entity-name peer0 \
        --entity-username peer0-${ORG_NAME}-un \
        --entity-password peer0-${ORG_NAME}-pw
    
    createEntity \
        --entity-name peer1 \
        --entity-username peer1-${ORG_NAME}-un \
        --entity-password peer1-${ORG_NAME}-pw
    
    createEntityTLS \
        --entity-name peer1 \
        --entity-username peer1-${ORG_NAME}-un \
        --entity-password peer1-${ORG_NAME}-pw

done




############################################################## 
# GENERATING CRYPTO-MATERIALS - ORDERERS
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING CRYPTO-MATERIALS - orderers\n\n${C_RESET}"

KUBERNETES_ORG_CA_HOSTNAME=ca-orderers
ORG_CA_ADMIN_USERNAME=admin
ORG_CA_ADMIN_PASSWORD=adminpw

source create-crypto.sh \
    --org-name orderers \
    --org-ca-hostname ${KUBERNETES_ORG_CA_HOSTNAME} \
    --org-ca-admin-username ${ORG_CA_ADMIN_USERNAME} \
    --org-ca-admin-password ${ORG_CA_ADMIN_PASSWORD} \
    --tls-ca-hostname ${KUBERNETES_TLS_CA_HOSTNAME} \
    --tls-ca-admin-username ${TLS_CA_ADMIN_USERNAME} \
    --tls-ca-admin-password ${TLS_CA_ADMIN_PASSWORD}

createOrg

createEntity \
    --entity-name orderer0 \
    --entity-username orderer0-orderers-un \
    --entity-password orderer0-orderers-pw

createEntityTLS \
    --entity-name orderer0 \
    --entity-username orderer0-orderers-un \
    --entity-password orderer0-orderers-pw

createEntity \
    --entity-name orderer1 \
    --entity-username orderer1-orderers-un \
    --entity-password orderer1-orderers-pw

createEntityTLS \
    --entity-name orderer1 \
    --entity-username orderer1-orderers-un \
    --entity-password orderer1-orderers-pw

createEntity \
    --entity-name orderer2 \
    --entity-username orderer2-orderers-un \
    --entity-password orderer2-orderers-pw

createEntityTLS \
    --entity-name orderer2 \
    --entity-username orderer2-orderers-un \
    --entity-password orderer2-orderers-pw




############################################################## 
# GENERATING GENESIS BLOCK 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING GENESIS BLOCK\n\n${C_RESET}"

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath ${CONFIGTX_HOME} \
    -profile TwoOrgOrdererGenesis \
    -channelID ${SYS_CHANNEL_NAME} \
    -outputBlock ${CONFIGTX_HOME}/genesis.block

###################### INTERNAL COMMAND ######################'




############################################################## 
# GENERATING BASE APPLICATION CHANNEL CREATION TRANSACTION 
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING APPLICATION CHANNEL CREATION TRANSACTION - ${BASE_CHANNEL_NAME}\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath ${CONFIGTX_HOME} \
    -profile TwoOrgChannel \
    -channelID '${BASE_CHANNEL_NAME}' \
    -outputCreateChannelTx ${CONFIGTX_HOME}/'${BASE_CHANNEL_NAME}'.tx

###################### INTERNAL COMMAND ######################'




############################################################## 
# GENERATING BASE ANCHOR PEER TRANSACTIONS 
##############################################################

for ORG_NAME in "org1" "org2"; do

    printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > GENERATING ANCHOR PEER UPDATE TRANSACTION - ${ORG_NAME}\n\n${C_RESET}"

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath ${CONFIGTX_HOME} \
    -profile TwoOrgChannel \
    -channelID '${BASE_CHANNEL_NAME}' \
    -asOrg '${ORG_NAME^}'MSP \
    -outputAnchorPeersUpdate ${CONFIGTX_HOME}/'${ORG_NAME^}'MSPanchors.tx

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# STARTING BASE PEER SERVICES
##############################################################

printf "${C_BLUE_BOLD}\nstart.sh:${C_BLUE}\n > STARTING BASE PEER SERVICES\n\n${C_RESET}"

# orderers
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer0-orderers.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer1-orderers.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/orderers/orderer2-orderers.yaml

# peers
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org1/peer0-org1.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org1/peer1-org1.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org2/peer0-org2.yaml
kubectl apply -f ${SCRIPT}/kubernetes-manifests/base/org2/peer1-org2.yaml

# wait for all containers to start
while kubectl get pods | grep 'ContainerCreating'; do
    sleep 10
done
sleep 10

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
    -o ${ORDERER_ENDPOINT} \
    -c '${BASE_CHANNEL_NAME}' \
    -f ${CONFIGTX_HOME}/'${BASE_CHANNEL_NAME}'.tx \
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
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt

peer channel fetch oldest '${BASE_CHANNEL_NAME}'.block \
    -o ${ORDERER_ENDPOINT} \
    -c '${BASE_CHANNEL_NAME}' \
    --tls --cafile ${ORDERER_TLS_CA}

while sleep 10; do
    peer channel join \
        -b '${BASE_CHANNEL_NAME}'.block
    if [ $? -eq 0 ]; then
        break
    fi
done

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
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/ca.crt

peer channel update \
    -o ${ORDERER_ENDPOINT} \
    -c '${BASE_CHANNEL_NAME}' \
    -f ${CONFIGTX_HOME}/'${ORG_NAME^}'MSPanchors.tx \
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
    --configFile ${CONFIGTX_HOME}/discovery-conf-'${ORG_NAME}'.yaml \
    --tlsCert ${CORE_PEER_TLS_CERT_FILE} \
    --tlsKey ${CORE_PEER_TLS_KEY_FILE} \
    --peerTLSCA ${CORE_PEER_TLS_ROOTCERT_FILE} \
    --userKey $(ls ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/keystore/* | head -n 1) \
    --userCert ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/signcerts/cert.pem \
    --MSP '${ORG_NAME^}'MSP \
    saveConfig

###################### INTERNAL COMMAND ######################'

done