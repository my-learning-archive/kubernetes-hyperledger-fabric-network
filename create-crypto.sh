#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES 
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,org-name:,org-ca-hostname:,org-ca-admin-username:,org-ca-admin-password:,tls-ca-hostname:,tls-ca-admin-username:,tls-ca-admin-password: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
    case "$1" in
        -h | --help)
            printf "${C_BLUE_BOLD}\ncreate-user.sh:${C_BLUE}\n > HELP:\n\n${C_RESET}"
            echo -e "Usage $0 [--<flags> <values>]"
            echo -e "\nRequired flags:"
            echo -e "  --org-name: The name of the Hyperledger Fabric organization the contacted CAs belong to."
            echo -e "  --org-ca-hostname: The hostname of the Hyperledger Fabric organizational CA, for the generation of MSP certificates."
            echo -e "  --org-ca-admin-username: The username of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --org-ca-admin-password: The password of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --tls-ca-hostname: The hostname of the TLS CA, for the generation of TLS certificates."
            echo -e "  --tls-ca-admin-username: The username of the TLS CA admin, for the generation of TLS certificates."
            echo -e "  --tls-ca-admin-password: The password of TLS CA admin, for the generation of TLS certificates."
            exit 1
            ;;
        --org-name)
            ORG_NAME=$2
            shift 2
            ;;
        --org-ca-hostname)
            ORG_CA_HOSTNAME=$2
            shift 2
            ;;
        --org-ca-admin-username)
            ORG_CA_ADMIN_USERNAME=$2
            shift 2
            ;;
        --org-ca-admin-password)
            ORG_CA_ADMIN_PASSWORD=$2
            shift 2
            ;;
        --tls-ca-hostname)
            TLS_CA_HOSTNAME=$2
            shift 2
            ;;
        --tls-ca-admin-username)
            TLS_CA_ADMIN_USERNAME=$2
            shift 2
            ;;
        --tls-ca-admin-password)
            TLS_CA_ADMIN_PASSWORD=$2
            shift 2
            ;;
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ncrypto-config.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=${ORG_NAME}
ORG_CA_HOSTNAME=${ORG_CA_HOSTNAME}
ORG_CA_ADMIN_USERNAME=${ORG_CA_ADMIN_USERNAME}
ORG_CA_ADMIN_PASSWORD=${ORG_CA_ADMIN_PASSWORD}
TLS_CA_HOSTNAME=${TLS_CA_HOSTNAME}
TLS_CA_ADMIN_USERNAME=${TLS_CA_ADMIN_USERNAME}
TLS_CA_ADMIN_PASSWORD=${TLS_CA_ADMIN_PASSWORD}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${ORG_CA_HOSTNAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_HOSTNAME} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
    exit 1   
}




############################################################## 
# PROCESSING VARIABLES 
##############################################################

# in the .env file
KUBERNETES_CA_CLI_HOSTNAME=${ENV_KUBERNETES_CA_CLI_HOSTNAME}

KUBERNETES_CA_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CA_CLI_HOSTNAME}-* | awk '{print $1}')

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
    ORG_CA_TLS_CERTIFICATE=${ORG_CRYPTO_MATERIAL_TARGET}/ca/${ORG_CA_HOSTNAME}-cert.pem
}

TLS_CA_TLS_CERTIFICATE=${CA_CLI_INTERNAL_CRYPTO_CONFIG_PATH}/externalServices/${TLS_CA_HOSTNAME}/tlsca/${TLS_CA_HOSTNAME}-cert.pem




############################################################## 
# ENROLLING CA ADMIN 
##############################################################

echo -e "${C_BLUE}\nEnrolling organizational CA admin ...${C_RESET}"

kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${ORG_CA_ADMIN_USERNAME}':'${ORG_CA_ADMIN_PASSWORD}'@'${ORG_CA_HOSTNAME}':7054 \
    --caname '${ORG_CA_HOSTNAME}' \
    -M '${ORG_CRYPTO_MATERIAL_TARGET}'/msp \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'

echo -e "${C_BLUE}\nEnrolling TLS CA admin ...${C_RESET}"

kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'
fabric-ca-client enroll \
    -u https://'${TLS_CA_ADMIN_USERNAME}':'${TLS_CA_ADMIN_PASSWORD}'@'${TLS_CA_HOSTNAME}':7054 \
    --caname '${TLS_CA_HOSTNAME}' \
    -M '${ORG_CRYPTO_MATERIAL_TARGET}'/tls \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'




############################################################## 
# FUNCTION: Creating Org Crypto
##############################################################

function createOrg(){

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

mkdir -p '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/cacerts

cat << EOF > '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/config.yaml
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'-7054-'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'-7054-'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'-7054-'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/'${ORG_CA_HOSTNAME}'-7054-'${ORG_CA_HOSTNAME}'.pem
    OrganizationalUnitIdentifier: orderer
'EOF'

###################### INTERNAL COMMAND ######################'

    createUser \
        --user-type admin \
        --user-username ${ORG_NAME}admin \
        --user-password ${ORG_NAME}adminpw
    
    createUserTLS \
        --user-type admin \
        --user-hostname host.minikube.internal \
        --user-username ${ORG_NAME}admin \
        --user-password ${ORG_NAME}adminpw
}




############################################################## 
# FUNCTION: Creating User Identity Crypto
##############################################################

function createUser(){

    VALID_ARGS=$(getopt -o h\0 --long user-type:,user-role:,user-username:,user-password: -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi

    eval set -- "$VALID_ARGS"
    while [ : ]; do
        case "$1" in
            --user-type)
                USER_TYPE=$2
                shift 2
                ;;
            --user-role)
                USER_ROLE=$2
                shift 2
                ;;
            --user-username)
                USER_USERNAME=$2
                shift 2
                ;;
            --user-password)
                USER_PASSWORD=$2
                shift 2
                ;;
            --) shift; 
                break 
                ;;
        esac
    done
    
    USER_TYPE=${USER_TYPE}
    USER_ROLE=${USER_ROLE:-"NA"}
    USER_USERNAME=${USER_USERNAME}
    USER_PASSWORD=${USER_PASSWORD}

    [[ -z ${USER_TYPE} || -z ${USER_ROLE} || -z ${USER_USERNAME} || -z ${USER_PASSWORD} ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
        exit 1   
    }

    [[ ${USER_ROLE} == "NA" ]] || {
        USER_ROLE_FLAG="--id.attrs role=${USER_ROLE}:ecert"
    }

    USER_MSP_PATH=${ORG_CRYPTO_MATERIAL_TARGET}/users/${USER_USERNAME}@${ORG_NAME}/msp

    echo -e "${C_BLUE}\nRegistering to organizational CA: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'

USER_ROLE_FLAG='"'${USER_ROLE_FLAG}'"'

fabric-ca-client register \
    --caname '${ORG_CA_HOSTNAME}' \
    --id.name '${USER_USERNAME}' \
    --id.secret '${USER_PASSWORD}' \
    --id.type '${USER_TYPE}' ${USER_ROLE_FLAG} \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'

    echo -e "${C_BLUE}\nGenerating MSP: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'

fabric-ca-client enroll \
    -u https://'${USER_USERNAME}':'${USER_PASSWORD}'@'${ORG_CA_HOSTNAME}':7054 \
    --caname '${ORG_CA_HOSTNAME}' \
    -M '${USER_MSP_PATH}' \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'
cp '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/config.yaml '${USER_MSP_PATH}'/config.yaml

###################### INTERNAL COMMAND ######################'
}




############################################################## 
# FUNCTION: Creating User TLS Crypto
##############################################################

function createUserTLS(){

    VALID_ARGS=$(getopt -o h\0 --long user-type:,user-role:,user-hostname:,user-username:,user-password: -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi

    eval set -- "$VALID_ARGS"
    while [ : ]; do
        case "$1" in
            --user-type)
                USER_TYPE=$2
                shift 2
                ;;
            --user-role)
                USER_ROLE=$2
                shift 2
                ;;
            --user-hostname)
                USER_HOSTNAME=$2
                shift 2
                ;;
            --user-username)
                USER_USERNAME=$2
                shift 2
                ;;
            --user-password)
                USER_PASSWORD=$2
                shift 2
                ;;
            --) shift; 
                break 
                ;;
        esac
    done
    
    USER_TYPE=${USER_TYPE}
    USER_ROLE=${USER_ROLE:-"NA"}
    USER_HOSTNAME=${USER_HOSTNAME}
    USER_USERNAME=${USER_USERNAME}
    USER_PASSWORD=${USER_PASSWORD}

    [[ -z ${USER_TYPE} || -z ${USER_ROLE} || -z ${USER_HOSTNAME} || -z ${USER_USERNAME} || -z ${USER_PASSWORD} ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
        exit 1   
    }

    [[ ${USER_ROLE} == "NA" ]] || {
        USER_ROLE_FLAG="--id.attrs role=${USER_ROLE}:ecert"
    }

    USER_TLS_PATH=${ORG_CRYPTO_MATERIAL_TARGET}/users/${USER_USERNAME}@${ORG_NAME}/tls

    echo -e "${C_BLUE}\nRegistering to TLS CA: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'

USER_ROLE_FLAG='"'${USER_ROLE_FLAG}'"'

fabric-ca-client register \
    --caname '${TLS_CA_HOSTNAME}' \
    --id.name '${USER_USERNAME}' \
    --id.secret '${USER_PASSWORD}' \
    --id.type '${USER_TYPE}' ${USER_ROLE_FLAG} \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'

    echo -e "${C_BLUE}\nGenerating TLS: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'

fabric-ca-client enroll \
    -u https://'${USER_USERNAME}':'${USER_PASSWORD}'@'${TLS_CA_HOSTNAME}':7054 \
    --caname '${TLS_CA_HOSTNAME}' \
    -M '${USER_TLS_PATH}' \
    --csr.hosts '${USER_HOSTNAME}' \
    --enrollment.profile tls \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'

cp '${USER_TLS_PATH}'/tlscacerts/* '${USER_TLS_PATH}'/ca.crt
cp '${USER_TLS_PATH}'/signcerts/* '${USER_TLS_PATH}'/client.crt
cp '${USER_TLS_PATH}'/keystore/* '${USER_TLS_PATH}'/client.key

###################### INTERNAL COMMAND ######################'
}




############################################################## 
# FUNCTION: Creating Entity Identity Crypto
##############################################################

function createEntity(){

    VALID_ARGS=$(getopt -o h\0 --long entity-name:,entity-username:,entity-password: -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi

    eval set -- "$VALID_ARGS"
    while [ : ]; do
        case "$1" in
            --entity-name)
                ENTITY_NAME=$2
                shift 2
                ;;
            --entity-username)
                ENTITY_USERNAME=$2
                shift 2
                ;;
            --entity-password)
                ENTITY_PASSWORD=$2
                shift 2
                ;;
            --) shift; 
                break 
                ;;
        esac
    done
    
    ENTITY_NAME=${ENTITY_NAME}
    ENTITY_USERNAME=${ENTITY_USERNAME}
    ENTITY_PASSWORD=${ENTITY_PASSWORD}

    [[ -z ${ENTITY_NAME} || -z ${ENTITY_USERNAME} || -z ${ENTITY_PASSWORD} ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
        exit 1   
    }

    ENTITY_MSP_PATH=${ORG_CRYPTO_MATERIAL_TARGET}/${ENTITY_TYPE}s/${ENTITY_NAME}-${ORG_NAME}/msp

    echo -e "${C_BLUE}\nRegistering to organizational CA: ${ENTITY_NAME}-${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'

fabric-ca-client register \
    --caname '${ORG_CA_HOSTNAME}' \
    --id.name '${ENTITY_USERNAME}' \
    --id.secret '${ENTITY_PASSWORD}' \
    --id.type '${ENTITY_TYPE}' \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'

    echo -e "${C_BLUE}\nGenerating MSP: ${ENTITY_NAME}-${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${ORG_CA_HOSTNAME}'

fabric-ca-client enroll \
    -u https://'${ENTITY_USERNAME}':'${ENTITY_PASSWORD}'@'${ORG_CA_HOSTNAME}':7054 \
    --caname '${ORG_CA_HOSTNAME}' \
    -M '${ENTITY_MSP_PATH}' \
    --tls.certfiles '${ORG_CA_TLS_CERTIFICATE}' \
    --csr.hosts '${ENTITY_NAME}'-'${ORG_NAME}'

cp '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/config.yaml '${ENTITY_MSP_PATH}'/config.yaml

###################### INTERNAL COMMAND ######################'
}




############################################################## 
# FUNCTION: Creating Entity TLS Crypto
##############################################################

function createEntityTLS(){

    VALID_ARGS=$(getopt -o h\0 --long entity-name:,entity-username:,entity-password: -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi

    eval set -- "$VALID_ARGS"
    while [ : ]; do
        case "$1" in
            --entity-name)
                ENTITY_NAME=$2
                shift 2
                ;;
            --entity-username)
                ENTITY_USERNAME=$2
                shift 2
                ;;
            --entity-password)
                ENTITY_PASSWORD=$2
                shift 2
                ;;
            --) shift; 
                break 
                ;;
        esac
    done
    
    ENTITY_NAME=${ENTITY_NAME}
    ENTITY_USERNAME=${ENTITY_USERNAME}
    ENTITY_PASSWORD=${ENTITY_PASSWORD}

    [[ -z ${ENTITY_NAME} || -z ${ENTITY_USERNAME} || -z ${ENTITY_PASSWORD} ]] && {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
        exit 1   
    }

    ENTITY_TLS_PATH=${ORG_CRYPTO_MATERIAL_TARGET}/${ENTITY_TYPE}s/${ENTITY_NAME}-${ORG_NAME}/tls

    echo -e "${C_BLUE}\nRegistering to TLS CA: ${USER_USERNAME}@${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'

fabric-ca-client register \
    --caname '${TLS_CA_HOSTNAME}' \
    --id.name '${ENTITY_USERNAME}' \
    --id.secret '${ENTITY_PASSWORD}' \
    --id.type '${ENTITY_TYPE}' \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'

###################### INTERNAL COMMAND ######################'

    echo -e "${C_BLUE}\nGenerating TLS: ${ENTITY_NAME}-${ORG_NAME} ...${C_RESET}"

    kubectl exec -it ${KUBERNETES_CA_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export FABRIC_CA_CLIENT_HOME=$FABRIC_CA_HOME/client/'${TLS_CA_HOSTNAME}'

fabric-ca-client enroll \
    -u https://'${ENTITY_USERNAME}':'${ENTITY_PASSWORD}'@'${TLS_CA_HOSTNAME}':7054 \
    --caname '${TLS_CA_HOSTNAME}' \
    -M '${ENTITY_TLS_PATH}' \
    --csr.hosts '${ENTITY_NAME}'-'${ORG_NAME}' \
    --csr.hosts 'cli' \
    --enrollment.profile tls \
    --tls.certfiles '${TLS_CA_TLS_CERTIFICATE}'

cp '${ENTITY_TLS_PATH}'/tlscacerts/* '${ENTITY_TLS_PATH}'/ca.crt
cp '${ENTITY_TLS_PATH}'/signcerts/* '${ENTITY_TLS_PATH}'/server.crt
cp '${ENTITY_TLS_PATH}'/keystore/* '${ENTITY_TLS_PATH}'/server.key

mkdir -p '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/tlscacerts
cp '${ENTITY_TLS_PATH}'/tlscacerts/* '${ORG_CRYPTO_MATERIAL_TARGET}'/msp/tlscacerts/ca.crt

###################### INTERNAL COMMAND ######################'
}