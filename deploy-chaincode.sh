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
    CORE_PEER_TLS_CERT_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.crt
    CORE_PEER_TLS_KEY_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/ca.crt
    CORE_PEER_TLS_CLIENTCERT_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.crt
    CORE_PEER_TLS_CLIENTKEY_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/server.key
    CORE_PEER_TLS_CLIENTROOTCERT_FILE=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/peers/${PEER_HOSTNAME}/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=\${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/users/${ORG_NAME}admin@${ORG_NAME}/msp
}

##############################################################
# FUNCTIONS - END
##############################################################




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,chaincode-label:,chaincode-version:,channel-name:,channel-org-name:,collections-config:,signature-policy: -- "$@")
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
            echo -e "  --chaincode-label: The label of deployed chaincode."
            echo -e "  --chaincode-version: The version of the deployed chaincode."           
            echo -e "  --channel-name: The name of the Hyperledger Fabric application channel the chaincode will be deployed to."
            echo -e "  --channel-org-name: The name of one of one Hyperledger Fabric organization in the channel the chaincode will be deployed to."
            echo -e "\nOptional flags:"
            echo -e "  --collections-config: The configuration file for the collections of the deployed chaincode, if applicable."
            echo -e "  --signature-policy: The signature policy of the deployed chaincode, if applicable."
            exit 1
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
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
CHAINCODE_LABEL=${CHAINCODE_LABEL}
CHAINCODE_VERSION=${CHAINCODE_VERSION}
CHANNEL_NAME=${CHANNEL_NAME}
CHANNEL_ORG_NAME=${CHANNEL_ORG_NAME}
COLLECTIONS_CONFIG=${COLLECTIONS_CONFIG:-"NA"}
SIGNATURE_POLICY=${SIGNATURE_POLICY:-"NA"}
{ set +x; } 2>/dev/null

[[ -z ${CHAINCODE_LABEL} || -z ${CHAINCODE_VERSION} || -z ${CHANNEL_NAME} || -z ${CHANNEL_ORG_NAME} || -z ${COLLECTIONS_CONFIG} || -z ${SIGNATURE_POLICY} ]] && {
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

[[ ${PEERS_LIST} == "" ]] && {
  >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} could not get the list of peers in the ${CHANNEL_NAME} channel - check if ${CHANNEL_NAME} exists or if ${CHANNEL_ORG_NAME} belongs to it!${C_RESET}"
  exit 1  
}

# peer parameters for long commands
PEER_PARAMETERS=""
for PEER_HOSTNAME in ${PEERS_LIST}; do
  assumeRole ${PEER_HOSTNAME} 1
  PEER_PARAMETERS="${PEER_PARAMETERS} --peerAddresses ${CORE_PEER_ADDRESS} --tlsRootCertFiles ${CORE_PEER_TLS_ROOTCERT_FILE}"
done

# additional flags
[[ ${COLLECTIONS_CONFIG} == "NA" ]] || {
  COLLECTIONS_CONFIG_FLAG="--collections-config ${CLI_CHAINCODE_DIR}/${COLLECTIONS_CONFIG}"
}

[[ ${SIGNATURE_POLICY} == "NA" ]] || {
  SIGNATURE_POLICY_FLAG=$(echo "--signature-policy ${SIGNATURE_POLICY}" | sed 's/'\''/%/g')
}




############################################################## 
# PACKAGING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > PACKAGING CHAINCODE\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    ORG_NAME=$(echo ${ORG_NAME} |  sed 's/\r$//')

    kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

BUILD_COMMAND='"'${BUILD_COMMAND}'"'

mkdir -p ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'
cd ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'

cat << EOF > connection.json
{
    "address": "chaincode-'${CHAINCODE_LABEL}'-'${ORG_NAME}':7052",
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
ls ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz

###################### INTERNAL COMMAND ######################'

done




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

peer lifecycle chaincode install ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz

peer lifecycle chaincode calculatepackageid ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz > /tmp/'${CHAINCODE_LABEL}'-'${ORG_NAME}'-package-id
cat /tmp/'${CHAINCODE_LABEL}'-'${ORG_NAME}'-package-id

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# STARTING EXTERNAL BUILDER SERVICES
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > STARTING EXTERNAL BUILDER SERVICES\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    ORG_NAME=$(echo ${ORG_NAME} |  sed 's/\r$//')
    PACKAGE_ID=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c 'cat /tmp/'${CHAINCODE_LABEL}'-'${ORG_NAME}'-package-id' | sed 's/\r$//')

    mkdir -p ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/
    cat << EOF > ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${CHAINCODE_LABEL}-${ORG_NAME}.yaml
apiVersion: v1
kind: Service
metadata:
  name: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
  labels:
    app: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
spec:
  ports:
    - name: grpc
      port: 7052
      targetPort: 7052
  selector:
    app: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
  labels:
    app: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
spec:
  selector:
    matchLabels:
      app: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
    spec:
      containers:
        - image: chaincode-${CHAINCODE_LABEL}
          name: chaincode-${CHAINCODE_LABEL}-${ORG_NAME}
          imagePullPolicy: Never
          env:
            - name: CHAINCODE_CCID
              value: "${PACKAGE_ID}"
            - name: CHAINCODE_ADDRESS
              value: "0.0.0.0:7052"
          ports:
            - containerPort: 7052
EOF

kubectl apply -f ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${CHAINCODE_LABEL}-${ORG_NAME}.yaml

done

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
# APPROVING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > APPROVING CHAINCODE\n\n${C_RESET}"

for ORG_NAME in ${CHANNEL_ORGS_LIST}; do

    ORG_NAME=$(echo ${ORG_NAME} |  sed 's/\r$//')

    assumeRole peer0-${ORG_NAME}

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

COLLECTIONS_CONFIG_FLAG='"'${COLLECTIONS_CONFIG_FLAG}'"'
SIGNATURE_POLICY_FLAG=$(echo '"'${SIGNATURE_POLICY_FLAG}'"' | sed "s/%/'\''/g")

PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CHAINCODE_HOME}/'${CHAINCODE_LABEL}'/'${CHAINCODE_VERSION}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz)

peer lifecycle chaincode approveformyorg \
    --channelID '${CHANNEL_NAME}' \
    --name '${CHAINCODE_LABEL}' \
    --version '${CHAINCODE_VERSION}' \
    --init-required \
    --package-id ${PACKAGE_ID} \
    --sequence '${CHAINCODE_VERSION}' \
    -o ${ORDERER_ENDPOINT} \
    ${COLLECTIONS_CONFIG_FLAG} \
    ${SIGNATURE_POLICY_FLAG} \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################'

done




############################################################## 
# COMMITING CHAINCODE
##############################################################

printf "${C_BLUE_BOLD}\ndeploy-chaincode.sh:${C_GRAY_ITALIC} ${CHAINCODE_LABEL}:${CHAINCODE_VERSION} ${C_BLUE}\n > COMMITTING CHAINCODE\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

COLLECTIONS_CONFIG_FLAG='"'${COLLECTIONS_CONFIG_FLAG}'"'
SIGNATURE_POLICY_FLAG=$(echo '"'${SIGNATURE_POLICY_FLAG}'"' | sed "s/%/'\''/g")
PEER_PARAMETERS=$(eval echo'"'${PEER_PARAMETERS}'"')

peer lifecycle chaincode commit \
    --channelID '${CHANNEL_NAME}' \
    --name '${CHAINCODE_LABEL}' \
    --version '${CHAINCODE_VERSION}' \
    --init-required \
    --sequence '${CHAINCODE_VERSION}' \
    -o ${ORDERER_ENDPOINT} \
    ${COLLECTIONS_CONFIG_FLAG} \
    ${SIGNATURE_POLICY_FLAG} \
    ${PEER_PARAMETERS} \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################'