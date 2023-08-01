#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,chaincode-image:,chaincode-label:,chaincode-version:,channel-name:,channel-org-name:,collections-config:,signature-policy:,init-required: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
    case "$1" in
        -h | --help)
            printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_BLUE}\n > HELP\n\n${C_RESET}"
            echo -e "Usage:"
            echo -e "  $0 [--<flags> <values>]"
            echo -e "\nRequired flags:"
            echo -e "  --chaincode-image: The container image of deployed chaincode - must be available within the Kubernetes cluster."
            echo -e "  --chaincode-label: The label of deployed chaincode."
            echo -e "  --chaincode-version: The version of the deployed chaincode."           
            echo -e "  --channel-name: The name of the Hyperledger Fabric application channel the chaincode will be deployed to."
            echo -e "  --channel-org-name: The name of one of one Hyperledger Fabric organization in the channel the chaincode will be deployed to."
            echo -e "\nOptional flags:"
            echo -e "  --collections-config: The local path to the configuration file for the collections of the deployed chaincode, if applicable."
            echo -e "  --signature-policy: The signature policy of the deployed chaincode, if applicable."
            echo -e "  --init-required: Specifies whether or not - 'true' or 'false' - the deployed chaincode requires an init function invoked before usage. If not specified, defaults to 'false'."
            exit 1
            ;;
        --chaincode-image)
            CHAINCODE_IMAGE=$2
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
        --init-required)
            INIT_REQUIRED=$2
            shift 2
            ;;
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
CHAINCODE_IMAGE=${CHAINCODE_IMAGE}
CHAINCODE_LABEL=${CHAINCODE_LABEL}
CHAINCODE_VERSION=${CHAINCODE_VERSION}
CHANNEL_NAME=${CHANNEL_NAME}
CHANNEL_ORG_NAME=${CHANNEL_ORG_NAME}
COLLECTIONS_CONFIG=${COLLECTIONS_CONFIG:-"NA"}
SIGNATURE_POLICY=${SIGNATURE_POLICY:-"NA"}
INIT_REQUIRED=${INIT_REQUIRED:-false}
{ set +x; } 2>/dev/null

[[ -z ${CHAINCODE_IMAGE} || -z ${CHAINCODE_LABEL} || -z ${CHAINCODE_VERSION} || -z ${CHANNEL_NAME} || -z ${CHANNEL_ORG_NAME} || -z ${COLLECTIONS_CONFIG} || -z ${SIGNATURE_POLICY} || -z ${INIT_REQUIRED} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more mandatory arguments have not been provided. Exiting. ${C_RESET}"
    exit 1   
}

[[ ${INIT_REQUIRED} == true || ${INIT_REQUIRED} == false ]] || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Invalid value for the --init-required flag - must be either 'true' or 'false'. Exiting. ${C_RESET}"
    exit 1    
}

[[ ${CHANNEL_NAME} == "NA" ]] || {
    [[ ${CHANNEL_ORG_NAME} == "NA" ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} An Hyperledger Fabric organization belonging to the specified application channel has not been provided. Exiting. ${C_RESET}"
        exit 1
    }
}




############################################################## 
# PROCESSING VARIABLES
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')

# list of orgs in target channel
CHANNEL_ORGS_LIST=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c 'discover --configFile ${CONFIGTX_HOME}/peerOrganizations/'${CHANNEL_ORG_NAME}'/discovery-conf-'${CHANNEL_ORG_NAME}'.yaml config --channel '${CHANNEL_NAME}' --server peer0-'${CHANNEL_ORG_NAME}':7051' | grep name | grep -v "Orderer" | awk '{print $2}' | tr -d '",MSP' | tr '[:upper:]' '[:lower:]' | sort | uniq | sed 's/\r$//')

# list of peers in target channel
PEERS_LIST=""
for ORG_NAME in ${CHANNEL_ORGS_LIST}; do
    PEERS_LIST="${PEERS_LIST} "$(kubectl get services | awk '{print $1}' | grep ^peer | grep ${ORG_NAME} | sort)
done

[[ ${PEERS_LIST} == "" ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not get the list of peers in the ${CHANNEL_NAME} channel - either ${CHANNEL_NAME} does not exist or ${CHANNEL_ORG_NAME} does not belong to it. Exiting. ${C_RESET}"
    exit 1  
}

# peer parameters for long commands
PEER_PARAMETERS=""
for PEER_HOSTNAME in ${PEERS_LIST}; do
    ORG_NAME=${PEER_HOSTNAME#*-}
    PEER_PARAMETERS="${PEER_PARAMETERS} --peerAddresses ${PEER_HOSTNAME}:7051 --tlsRootCertFiles \${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/ca.crt"
done

# additional flags
[[ ${COLLECTIONS_CONFIG} == "NA" ]] || {
    kubectl cp ${COLLECTIONS_CONFIG} ${KUBERNETES_CLI_POD_NAME}:/tmp/${CHAINCODE_LABEL}-collections-config.json # Hyperledger, c'mon... this is not cloud native...
    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

mkdir -p ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/
mv /tmp/'${CHAINCODE_LABEL}'-collections-config.json ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/collections-config.json

###################### INTERNAL COMMAND ######################'
    COLLECTIONS_CONFIG_FLAG="--collections-config \${CONFIGTX_HOME}/applicationChannels/${CHANNEL_NAME}/chaincodes/${CHAINCODE_LABEL}/collections-config.json"
}

[[ ${SIGNATURE_POLICY} == "NA" ]] || {
    SIGNATURE_POLICY_FLAG=$(echo "--signature-policy ${SIGNATURE_POLICY}" | sed 's/'\''/%/g')
}

[[ ${INIT_REQUIRED} == true ]] && {
    INIT_REQUIRED_FLAG="--init-required"
}




############################################################## 
# PACKAGING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > PACKAGING CHAINCODE\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

mkdir -p ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/
cd ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/

cat << EOF > connection.json
{
    "address": "chaincode-'${CHANNEL_NAME}'-'${CHAINCODE_LABEL}'-'${ORG_NAME}':7052",
    "dial_timeout": "10s",
    "tls_required": false,
    "client_auth_required": false,
    "client_key": "-----BEGIN EC PRIVATE KEY----- ... -----END EC PRIVATE KEY-----",
    "client_cert": "-----BEGIN CERTIFICATE----- ... -----END CERTIFICATE-----",
    "root_cert": "-----BEGIN CERTIFICATE---- ... -----END CERTIFICATE-----"
}
EOF

cat << EOF > metadata.json
{"path":"","type":"external","label":"'${CHAINCODE_LABEL}'"}
EOF

tar cfz code.tar.gz connection.json
tar cfz '${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz code.tar.gz metadata.json

rm -rvf connection.json code.tar.gz metadata.json &> /dev/null
ls ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz

###################### INTERNAL COMMAND ######################' || {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not package chaincode. Exiting. ${C_RESET}"
        exit 1
    }

done




############################################################## 
# INSTALLING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > INSTALLING CHAINCODE\n\n${C_RESET}"

for PEER_HOSTNAME in ${PEERS_LIST}; do

    echo -e "${C_BLUE}\nActing on behalf of ${PEER_HOSTNAME} ...${C_RESET}"

    ORG_NAME=${PEER_HOSTNAME#*-}

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
export CORE_PEER_ADDRESS='${PEER_HOSTNAME}':7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt

peer lifecycle chaincode install ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz

###################### INTERNAL COMMAND ######################' || {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not install chaincode. Exiting. ${C_RESET}"
        exit 1
    }

done




############################################################## 
# STARTING EXTERNAL BUILDER SERVICES
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > STARTING EXTERNAL BUILDER SERVICES\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    PACKAGE_ID=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c 'peer lifecycle chaincode calculatepackageid ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz' | sed 's/\r$//')

    mkdir -p ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/
    cat << EOF > ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}.yaml
apiVersion: v1
kind: Service
metadata:
  name: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
  labels:
    app: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
spec:
  ports:
    - name: grpc
      port: 7052
      targetPort: 7052
  selector:
    app: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
  labels:
    app: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
spec:
  selector:
    matchLabels:
      app: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
    spec:
      containers:
        - image: ${CHAINCODE_IMAGE}
          name: chaincode-${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}
          imagePullPolicy: Never
          env:
            - name: CHAINCODE_CCID
              value: "${PACKAGE_ID}"
            - name: CHAINCODE_ADDRESS
              value: "0.0.0.0:7052"
          ports:
            - containerPort: 7052
EOF

kubectl apply -f ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${CHANNEL_NAME}-${CHAINCODE_LABEL}-${ORG_NAME}.yaml

done

# wait for all containers to start
while kubectl get pods | grep 'ContainerCreating'; do
    sleep 10
done
sleep 10

# are all services are running?
[[ $(kubectl get pods | awk '{print $3}' | tail -n +2 | uniq) != "Running" ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more containers did not start. Exiting. ${C_RESET}"
    exit 1
} 




############################################################## 
# APPROVING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > APPROVING CHAINCODE\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    echo -e "${C_BLUE}\nActing on behalf of peer0-${ORG_NAME} ...${C_RESET}"

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

COLLECTIONS_CONFIG_FLAG=$(eval echo '"'${COLLECTIONS_CONFIG_FLAG}'"')
SIGNATURE_POLICY_FLAG=$(echo '"'${SIGNATURE_POLICY_FLAG}'"' | sed "s/%/'\''/g")

PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz)

peer lifecycle chaincode approveformyorg \
    --channelID '${CHANNEL_NAME}' \
    --name '${CHAINCODE_LABEL}' \
    --version '${CHAINCODE_VERSION}' \
    --package-id ${PACKAGE_ID} \
    --sequence '${CHAINCODE_VERSION}' \
    -o ${ORDERER_ENDPOINT} \
    ${COLLECTIONS_CONFIG_FLAG} \
    ${SIGNATURE_POLICY_FLAG} \
    '${INIT_REQUIRED_FLAG}' \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################' || {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not approve chaincode. Exiting. ${C_RESET}"
        exit 1
    }

done




############################################################## 
# COMMITING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > COMMITTING CHAINCODE\n\n${C_RESET}"

echo -e "${C_BLUE}\nActing on behalf of peer0-${CHANNEL_ORG_NAME} ...${C_RESET}"

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

COLLECTIONS_CONFIG_FLAG=$(eval echo '"'${COLLECTIONS_CONFIG_FLAG}'"')
SIGNATURE_POLICY_FLAG=$(echo '"'${SIGNATURE_POLICY_FLAG}'"' | sed "s/%/'\''/g")
PEER_PARAMETERS=$(eval echo '"'${PEER_PARAMETERS}'"')

peer lifecycle chaincode commit \
    --channelID '${CHANNEL_NAME}' \
    --name '${CHAINCODE_LABEL}' \
    --version '${CHAINCODE_VERSION}' \
    --sequence '${CHAINCODE_VERSION}' \
    -o ${ORDERER_ENDPOINT} \
    ${COLLECTIONS_CONFIG_FLAG} \
    ${SIGNATURE_POLICY_FLAG} \
    '${INIT_REQUIRED_FLAG}' \
    ${PEER_PARAMETERS} \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not commit chaincode. Exiting. ${C_RESET}"
    exit 1
}