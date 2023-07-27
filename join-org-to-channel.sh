#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,org-name:,channel-name:,channel-org-name: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
    case "$1" in
        -h | --help)
            printf "${C_BLUE_BOLD}\ncreate-user.sh:${C_BLUE}\n > HELP\n\n${C_RESET}"
            echo -e "Usage:"
            echo -e "  $0 [--<flags> <values>]"
            echo -e "\nRequired flags:"
            echo -e "  --org-name: The name of the Hyperledger Fabric organization to add to the channel."
            echo -e "  --channel_name: The name of a channel the Hyperledger Fabric organization should join."
            echo -e "  --channel_org_name: The name of one Hyperledger Fabric organization in the channel the created organization should join."
            exit 1
            ;;
        --org-name)
            ORG_NAME=$2
            shift 2
            ;;
        --channel-name)
            CHANNEL_NAME=$2
            shift 2
            ;;
        --channel-org-name)
            CHANNEL_ORG_NAME=$2
            shift 2
            ;;
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\njoin-org-to-channel.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=${ORG_NAME}
CHANNEL_NAME=${CHANNEL_NAME}
CHANNEL_ORG_NAME=${CHANNEL_ORG_NAME}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${CHANNEL_NAME} || -z ${CHANNEL_ORG_NAME} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
    exit 1   
}

[[ ${CHANNEL_NAME} == "NA" ]] || {
    [[ ${CHANNEL_ORG_NAME} == "NA" ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} you did not provide an organization that is part of the ${CHANNEL_NAME} channel!${C_RESET}"
        exit 1
    }
}




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')




############################################################## 
# JOINING ORGANIZATION TO APPLICATION CHANNEL
##############################################################

printf "${C_BLUE_BOLD}\njoin-org-to-channel.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > JOINING ORGANIZATION TO APPLICATION CHANNEL\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${CHANNEL_ORG_NAME^}'MSP
export CORE_PEER_ADDRESS=peer0-'${CHANNEL_ORG_NAME}':7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/users/'${CHANNEL_ORG_NAME}'admin@'${CHANNEL_ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/ca.crt

mkdir -p ${CONFIGTX_HOME}/expand/peerOrganizations/'${ORG_NAME}'/

[[ '${ORG_NAME}' == "org1" || '${ORG_NAME}' == "org2" ]] && {
    configtxgen \
        -configPath ${CONFIGTX_HOME}/ \
        -printOrg '${ORG_NAME^}'MSP > ${CONFIGTX_HOME}/expand/peerOrganizations/'${ORG_NAME}'/'${ORG_NAME}'-definition.json
}

cd ${CONFIGTX_HOME}/expand/peerOrganizations/'${ORG_NAME}'/

BLOCK_FETCHED_CONFIG_PB=blockFetchedConfig-'${CHANNEL_NAME}'-'${ORG_NAME}'.pb
CONFIG_BLOCK_JSON=configBlock-'${CHANNEL_NAME}'-'${ORG_NAME}'.json
CONFIG_BLOCK_PB=configBlock-'${CHANNEL_NAME}'-'${ORG_NAME}'.pb
CONFIG_CHANGES_JSON=configChanges-'${CHANNEL_NAME}'-'${ORG_NAME}'.json
CONFIG_CHANGES_PB=configChanges-'${CHANNEL_NAME}'-'${ORG_NAME}'.pb
CONFIG_PROPOSAL_JSON=configProposal-'${CHANNEL_NAME}'-'${ORG_NAME}'.json
CONFIG_PROPOSAL_PB=configProposal-'${CHANNEL_NAME}'-'${ORG_NAME}'.pb
SUBMIT_READY_JSON=submitReady-'${CHANNEL_NAME}'-'${ORG_NAME}'.json
SUBMIT_READY_PB=submitReady-'${CHANNEL_NAME}'-'${ORG_NAME}'.pb

peer channel fetch config ${BLOCK_FETCHED_CONFIG_PB} \
    -o ${ORDERER_ENDPOINT} \
    -c '${CHANNEL_NAME}' \
    --tls --cafile ${ORDERER_TLS_CA}

configtxlator proto_decode \
	--input ${BLOCK_FETCHED_CONFIG_PB} \
	--type common.Block | jq .data.data[0].payload.data.config > ${CONFIG_BLOCK_JSON}

jq -s '"'"'.[0] * {"channel_group":{"groups":{"Application":{"groups":{"'${ORG_NAME^}'MSP":.[1]}}}}}'"'"' ${CONFIG_BLOCK_JSON} '${ORG_NAME}'-definition.json > ${CONFIG_CHANGES_JSON}

configtxlator proto_encode \
	--input ${CONFIG_BLOCK_JSON} \
	--type common.Config \
	--output ${CONFIG_BLOCK_PB}

configtxlator proto_encode \
	--input ${CONFIG_CHANGES_JSON} \
	--type common.Config \
	--output ${CONFIG_CHANGES_PB}

configtxlator compute_update \
	--channel_id '${CHANNEL_NAME}' \
	--original ${CONFIG_BLOCK_PB} \
	--updated ${CONFIG_CHANGES_PB} \
	--output ${CONFIG_PROPOSAL_PB}

configtxlator proto_decode \
	--input ${CONFIG_PROPOSAL_PB} \
	--type common.ConfigUpdate | jq . > ${CONFIG_PROPOSAL_JSON}

echo '"'"'{"payload":{"header":{"channel_header":{"channel_id":"'"'"''${CHANNEL_NAME}''"'"'","type":2}},"data":{"config_update":'"'"'$(cat ${CONFIG_PROPOSAL_JSON})'"'"'}}}'"'"' | jq . > ${SUBMIT_READY_JSON}

configtxlator proto_encode \
	--input ${SUBMIT_READY_JSON} \
	--type common.Envelope \
	--output ${SUBMIT_READY_PB}

CHANNEL_ORGS_LIST=$(discover --configFile ${CONFIGTX_HOME}/discovery-conf-'${CHANNEL_ORG_NAME}'.yaml config --channel '${CHANNEL_NAME}' --server peer0-'${CHANNEL_ORG_NAME}':7051 | grep name | grep -v "Orderer" | awk '"'"'{print $2}'"'"' | tr -d '"'"'",MSP'"'"' | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"' | sort | uniq)

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    ORG_NAME=$(echo ${ORG_NAME} | sed "s/\r$//")

    [[ ${ORG_NAME} != '${ORG_NAME}' ]] && {

        export CORE_PEER_LOCALMSPID=${ORG_NAME^}MSP
        export CORE_PEER_ADDRESS=peer0-${ORG_NAME}:7051
        export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/users/${ORG_NAME}admin@${ORG_NAME}/msp
        export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/server.crt
        export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/server.key
        export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/ca.crt
        export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/server.crt
        export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/server.key
        export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls/ca.crt

        peer channel signconfigtx \
            -f ${SUBMIT_READY_PB}
    }
done

peer channel update \
	-o ${ORDERER_ENDPOINT} \
	-c '${CHANNEL_NAME}' \
	-f ${SUBMIT_READY_PB} \
	--tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################'




############################################################## 
# JOINING ANCHOR PEER TO APPLICATION CHANNEL
##############################################################

printf "${C_BLUE_BOLD}\njoin-org-to-channel.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > JOINING PEERS TO APPLICATION CHANNEL\n\n${C_RESET}"

PEERS_LIST=$(kubectl get services | awk '{print $1}' | grep ^peer | grep ${ORG_NAME} | sort)

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${CHANNEL_ORG_NAME^}'MSP
export CORE_PEER_ADDRESS=peer0-'${CHANNEL_ORG_NAME}':7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/users/'${CHANNEL_ORG_NAME}'admin@'${CHANNEL_ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/peers/peer0-'${CHANNEL_ORG_NAME}'/tls/ca.crt

CHANNEL_CHAINCODES_LIST=$(peer lifecycle chaincode querycommitted --channelID '${CHANNEL_NAME}' | tail -n +2 | tr -d "," | awk '"'"'{print $2}'"'"')

for PEER_HOSTNAME in '${PEERS_LIST}'; do

    export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
    export CORE_PEER_ADDRESS=${PEER_HOSTNAME}:7051
    export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
    export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/server.crt
    export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/server.key
    export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/ca.crt
    export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/server.crt
    export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/server.key
    export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/${PEER_HOSTNAME}/tls/ca.crt

    echo -e "'${C_BLUE}'\nJoining ${PEER_HOSTNAME} peer to application channel ...'${C_RESET}'"

    peer channel fetch oldest '${CHANNEL_NAME}'.block \
        -o ${ORDERER_ENDPOINT} \
        -c '${CHANNEL_NAME}' \
        --tls --cafile ${ORDERER_TLS_CA}
        
    while sleep 10; do
        peer channel join \
            -b '${CHANNEL_NAME}'.block
        if [ $? -eq 0 ]; then
            break
        fi
    done

    for CHAINCODE_LABEL in ${CHANNEL_CHAINCODES_LIST}; do
        echo -e "'${C_BLUE}'\nInstalling ${CHAINCODE_LABEL} chaincode in ${PEER_HOSTNAME} peer ...'${C_RESET}'"
        peer lifecycle chaincode install ${CHAINCODE_HOME}/${CHAINCODE_LABEL}/${CHAINCODE_LABEL}-'${ORG_NAME}'.tgz
    done

done

###################### INTERNAL COMMAND ######################'