#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




##############################################################
# FUNCTIONS - START
##############################################################

function assumeRole {

    PEER_HOSTNAME=$1

    OLDIFS=${IFS} && IFS='-' && read -a PEER_HOSTNAME_ARRAY <<< "${PEER_HOSTNAME}" && IFS=${OLDIFS}
    PEER_NAME=${PEER_HOSTNAME_ARRAY[0]}
    ORG_NAME=${PEER_HOSTNAME_ARRAY[1]}

    SUPRESS_VERBOSE=$2
    [[ ${SUPRESS_VERBOSE} -eq 1 ]] || echo -e "${C_BLUE}\nActing on behalf of ${PEER_HOSTNAME} ...${C_RESET}"

    CORE_PEER_LOCALMSPID=${ORG_NAME^}MSP
    CORE_PEER_ADDRESS=${PEER_HOSTNAME}:7051
    CORE_PEER_TLS_CERT_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.crt
    CORE_PEER_TLS_KEY_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/ca.crt
    CORE_PEER_TLS_CLIENTCERT_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.crt
    CORE_PEER_TLS_CLIENTKEY_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.key
    CORE_PEER_TLS_CLIENTROOTCERT_FILE='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH='${CRYPTO_HOME}'/peerOrganizations/${ORG_NAME}/users/${ORG_NAME}admin@${ORG_NAME}/msp
}

##############################################################
# FUNCTIONS - END
##############################################################




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,chaincode-relative-name:,chaincode-label:,chaincode-version:,chaincode-language:,channel-name:,channel-org-name:,collections-config:,signature-policy: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
    case "$1" in
        -h | --help)
            printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_BLUE}\n > HELP:\n\n${C_RESET}"
            echo -e "Usage:"
            echo -e "  $0 [--<flags> <values>]"
            echo -e "\nRequired flags:"
            echo -e "  --chaincode-relative-name: The name given to the relative path of the deployed chaincode inside the Hyperledger Fabric tools client container."
            echo -e "  --chaincode-label: The label of deployed chaincode."
            echo -e "  --chaincode-version: The version of the deployed chaincode."
            echo -e "  --chaincode-language: The language the deployed chaincode is written in - 'node' or 'golang'."            
            echo -e "  --channel-name: The name of the Hyperledger Fabric application channel the chaincode will be deployed to."
            echo -e "  --channel-org-name: The name of one of one Hyperledger Fabric organization in the channel the chaincode will be deployed to."
            echo -e "\nOptional flags:"
            echo -e "  --collections-config: The configuration file for the collections of the deployed chaincode, if applicable."
            echo -e "  --signature-policy: The signature policy of the deployed chaincode, if applicable."
            exit 1
            ;;
        --chaincode-relative-name)
            CHAINCODE_RELATIVE_NAME=$2
            shift 2
            ;;
        --chaincode-label)
            CHAINCODE_LABEL=$2
            shift 2
            ;;
        --chaincode-version)
            CHAINCODE_VERSION=$2
            shift 2
            ;;
        --chaincode-language)
            CHAINCODE_LANGUAGE=$2
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
        --collections-config)
            COLLECTIONS_CONFIG=$2
            shift 2
            ;;
        --signature-policy)
            SIGNATURE_POLICY=$2
            shift 2
            ;;
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
CHAINCODE_RELATIVE_NAME=${CHAINCODE_RELATIVE_NAME}
CHAINCODE_LABEL=${CHAINCODE_LABEL}
CHAINCODE_VERSION=${CHAINCODE_VERSION}
CHAINCODE_LANGUAGE=${CHAINCODE_LANGUAGE}
CHANNEL_NAME=${CHANNEL_NAME}
CHANNEL_ORG_NAME=${CHANNEL_ORG_NAME}
COLLECTIONS_CONFIG=${COLLECTIONS_CONFIG:-"NA"}
SIGNATURE_POLICY=${SIGNATURE_POLICY:-"NA"}
{ set +x; } 2>/dev/null

[[ -z ${CHAINCODE_RELATIVE_NAME} || -z ${CHAINCODE_LABEL} || -z ${CHAINCODE_VERSION} || -z ${CHAINCODE_LANGUAGE} || -z ${CHANNEL_NAME} || -z ${CHANNEL_ORG_NAME} || -z ${COLLECTIONS_CONFIG} || -z ${SIGNATURE_POLICY} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
    exit 1   
}




############################################################## 
# PROCESSING VARIABLES
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')

# list of orgs in target channel
CHANNEL_ORGS_LIST=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c 'discover --configFile ${CONFIGTX_HOME}/discovery-conf-'${CHANNEL_ORG_NAME}'.yaml config --channel '${CHANNEL_NAME}' --server peer0-'${CHANNEL_ORG_NAME}':7051' | grep name | grep -v "Orderer" | awk '{print $2}' | tr -d '",MSP' | tr '[:upper:]' '[:lower:]' | sort | uniq)

# list of peers in target channel
PEERS_LIST=""
for ORG_NAME in ${CHANNEL_ORGS_LIST}; do
  ORG_NAME=$(echo ${ORG_NAME} |  sed 's/\r$//')
  PEERS_LIST="${PEERS_LIST} "$(kubectl get services | awk '{print $1}' | grep ^peer | grep ${ORG_NAME} | sort)
done

# list of anchor peers in target channel
REPRESENTATIVE_PEERS_LIST=$(echo ${PEERS_LIST} | tr ' ' '\n' | grep ^peer0)

# peer parameters for long commands
PEER_PARAMETERS=""
for PEER_HOSTNAME in ${PEERS_LIST}; do
  assumeRole ${PEER_HOSTNAME} 1
  PEER_PARAMETERS="${PEER_PARAMETERS} --peerAddresses ${CORE_PEER_ADDRESS} --tlsRootCertFiles ${CORE_PEER_TLS_ROOTCERT_FILE}"
done




############################################################## 
# PACKAGING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > PACKAGING CHAINCODE\n\n${C_RESET}"

assumeRole peer0-${CHANNEL_ORG_NAME}

[[ ${CHAINCODE_LANGUAGE} == "node" ]] && BUILD_COMMAND="npm install"
[[ ${CHAINCODE_LANGUAGE} == "golang" ]] && BUILD_COMMAND="GO111MODULE=on go mod vendor"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

BUILD_COMMAND='"'${BUILD_COMMAND}'"'

cd ${CHAINCODE_HOME}/'${CHAINCODE_RELATIVE_NAME}'

eval ${BUILD_COMMAND}

peer lifecycle chaincode package ${CONFIGTX_HOME}/'${CHAINCODE_LABEL}'-package.tar.gz \
    --path ${CHAINCODE_HOME}/'${CHAINCODE_RELATIVE_NAME}' \
    --lang '${CHAINCODE_LANGUAGE}' \
    --label '${CHAINCODE_LABEL}'

###################### INTERNAL COMMAND ######################'




############################################################## 
# INSTALLING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > INSTALLING CHAINCODE\n\n${C_RESET}"

for PEER_HOSTNAME in ${PEERS_LIST}; do

    assumeRole ${PEER_HOSTNAME}

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${CORE_PEER_LOCALMSPID}'
export CORE_PEER_ADDRESS='${CORE_PEER_ADDRESS}'
export CORE_PEER_MSPCONFIGPATH='${CORE_PEER_MSPCONFIGPATH}'
export CORE_PEER_TLS_CERT_FILE='${CORE_PEER_TLS_CERT_FILE}'
export CORE_PEER_TLS_KEY_FILE='${CORE_PEER_TLS_KEY_FILE}'
export CORE_PEER_TLS_ROOTCERT_FILE='${CORE_PEER_TLS_ROOTCERT_FILE}'
export CORE_PEER_TLS_CLIENTROOTCAS_FILES='${CORE_PEER_TLS_CLIENTROOTCAS_FILES}'
export CORE_PEER_TLS_CLIENTCERT_FILE='${CORE_PEER_TLS_CLIENTCERT_FILE}'
export CORE_PEER_TLS_CLIENTKEY_FILE='${CORE_PEER_TLS_CLIENTKEY_FILE}'

peer lifecycle chaincode install ${CONFIGTX_HOME}/'${CHAINCODE_LABEL}'-package.tar.gz

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# APPROVING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > APPROVING CHAINCODE\n\n${C_RESET}"

for PEER_HOSTNAME in ${REPRESENTATIVE_PEERS_LIST}; do

    assumeRole ${PEER_HOSTNAME}

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CONFIGTX_HOME}/'${CHAINCODE_LABEL}'-package.tar.gz)

###################### INTERNAL COMMAND ######################'

done

exit 1


############################################################## 
# COMMITING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > COMMITTING CHAINCODE\n\n${C_RESET}"

# todo