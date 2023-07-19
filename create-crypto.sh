#!/bin/bash

set -o allexport && source .env && set +o allexport




############################################################## 
# INPUT VARIABLES 
##############################################################

set -x
ORG_NAME=$1
ORG_CA_HOSTNAME=$2
ORG_CA_ADMIN_USERNAME=$3
ORG_CA_ADMIN_PASSWORD=$4
TLS_CA_HOSTNAME=$5
TLS_CA_ADMIN_USERNAME=$6
TLS_CA_ADMIN_PASSWORD=$7
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${ORG_CA_HOSTNAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_HOSTNAME} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} ]] && {
  >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
  exit 1   
}




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CA_CLI_ENDPOINT=${ENV_KUBERNETES_CA_CLI_ENDPOINT}

CA_CLI_INTERNAL_CRYPTO_CONFIG_PATH='/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/'



############################################################## 
# PROCESSING DIRECTORIES 
##############################################################

[[ ${ORG_NAME} =~ ^org[1-99] ]] && {
    ENTITY_TYPE='peer'
    ORG_CRYPTO_MATERIAL_TARGET=${CA_CLI_INTERNAL_CRYPTO_CONFIG_PATH}/peerOrganizations/${ORG_NAME}
    ORG_CA_TLS_CERTIFICATE=${ORG_CRYPTO_MATERIAL_TARGET}/ca/${ORG_CA_HOSTNAME}-cert.pem
}

[[ ${ORG_NAME} == orderers ]] && {
    ENTITY_TYPE='orderer'
    ORG_CRYPTO_MATERIAL_TARGET=${CA_CLI_INTERNAL_CRYPTO_CONFIG_PATH}/ordererOrganizations/${ORG_NAME}
    ORG_CA_TLS_CERTIFICATE=${ORG_CRYPTO_MATERIAL_TARGET}/ca/${ORG_CA_HOSTNAME}-cert.pem}
}

TLS_CA_TLS_CERTIFICATE=${CA_CLI_INTERNAL_CRYPTO_CONFIG_PATH}/externalServices/${TLS_CA_HOSTNAME}/tlsca/${TLS_CA_HOSTNAME}-cert.pem




############################################################## 
# ENROLLING CA ADMIN 
##############################################################

echo -e "${C_BLUE}\nEnrolling organizational CA admin ...${C_RESET}"

kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${ORG_CA_ADMIN_USERNAME}':'${ORG_CA_ADMIN_PASSWORD}'@'${ORG_CA_HOSTNAME}':7054 \
    --caname '${ORG_CA_HOSTNAME}' \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'
'

echo -e "${C_BLUE}\nEnrolling TLS CA admin ...${C_RESET}"

kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${TLS_CA_ADMIN_USERNAME}':'${TLS_CA_ADMIN_PASSWORD}'@'${TLS_CA_HOSTNAME}':7054 \
    --caname '${TLS_CA_HOSTNAME}' \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'
'




############################################################## 
# FUNCTION: Creating Org Crypto
##############################################################

function createOrg(){

    kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
mkdir -p '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/
cat << EOF > '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/config.yaml
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: orderer
'EOF'
    '

    createUser "admin" "${ORG_NAME}admin" "${ORG_NAME}adminpw"
    createUserTLS "admin" "${ORG_NAME}admin" "${ORG_NAME}adminpw" "host.minikube.internal"
}




############################################################## 
# FUNCTION: Creating User Identity Crypto
##############################################################

function createUser(){
    
    USER_TYPE=$1
    USER_USERNAME=$2
    USER_PASSWORD=$3
    USER_ROLE=${4:-"NA"}

    [[ ${USER_ROLE} == "NA" ]] || {
        USER_ROLE_FLAG="--id.attrs role=${USER_ROLE}:ecert"
    }

    echo -e "${C_BLUE}\nRegistering to organizational CA: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'
fabric-ca-client register \
    --caname '${ORG_CA_HOSTNAME}' \
    --id.name '${USER_USERNAME}' \
    --id.secret '${USER_PASSWORD}' \
    --id.type '${USER_TYPE}' '${USER_ROLE_FLAG}' \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'
    '

    echo -e "${C_BLUE}\nGenerating MSP: ${USER_USERNAME}@${ORG_NAME}...${C_RESET}"

    kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${USER_USERNAME}':'${USER_PASSWORD}'@'${ORG_CA_HOSTNAME}':7054 \
    --caname '${ORG_CA_HOSTNAME}' \
    -M '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/msp \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'
cp '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/config.yaml '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/msp/config.yaml
    '
}




############################################################## 
# FUNCTION: Creating User TLS Crypto
##############################################################

function createUserTLS(){

    USER_TYPE=$1
    USER_USERNAME=$2
    USER_PASSWORD=$3
    USER_HOSTNAME=$4
    USER_ROLE=${5:-"NA"}

    [[ ${USER_ROLE} == "NA" ]] || {
        USER_ROLE_FLAG="--id.attrs role=${USER_ROLE}:ecert"
    }

    echo -e "${C_BLUE}\nRegistering to TLS CA: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'
fabric-ca-client register \
    --caname '${TLS_CA_HOSTNAME}' \
    --id.name '${USER_USERNAME}' \
    --id.secret '${USER_PASSWORD}' \
    --id.type '${USER_TYPE}' '${USER_ROLE_FLAG}' \
    --csr.hosts '${USER_ROLE}' \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'
    '

    echo -e "${C_BLUE}\nGenerating TLS: ${USER_USERNAME}@${ORG_NAME}...${C_RESET}"

    kubectl exec -it deploy/${KUBERNETES_CA_CLI_ENDPOINT} -- bash -c '
export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${USER_USERNAME}':'${USER_PASSWORD}'@'${TLS_CA_HOSTNAME}':7054 \
    --caname '${TLS_CA_HOSTNAME}' \
    -M '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls \
    --csr.hosts '${USER_ROLE}' \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'
cp '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/cacerts/* '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/ca.crt
cp '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/signcerts/* '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/client.crt
cp '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/keystore/* '${ORG_CRYPTO_MATERIAL_TARGET}'/users/'${USER_USERNAME}'@'${ORG_NAME}'/tls/client.key
    '
}




############################################################## 
# FUNCTION: Creating Entity Identity Crypto
##############################################################

# TODO




############################################################## 
# FUNCTION: Creating Entity TLS Crypto
##############################################################

# TODO



