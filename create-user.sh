#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,org-name:,user-type:,user-role:,user-hostname:,user-username:,user-password:,org-ca-admin-username:,org-ca-admin-password:,tls-ca-admin-username:,tls-ca-admin-password: -- "$@")
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
            echo -e "  --org-name: The name of the Hyperledger Fabric organization the created user will belong to."
            echo -e "  --user-type: The type of the created user - 'client' or 'admin'."
            echo -e "  --user-hostname: The hostname of the machine the created user will be represented by."
            echo -e "  --user-username: The username of the created user, for the generation of TLS certificates."
            echo -e "  --user-password: The password of the created user, for the generation of TLS certificates."
            echo -e "  --org-ca-admin-username: The username of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --org-ca-admin-password: The password of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --tls-ca-admin-username: The username of the TLS CA admin, for the generation of TLS certificates."
            echo -e "  --tls-ca-admin-password: The password of TLS CA admin, for the generation of TLS certificates."
            echo -e "\nOptional flags:"
            echo -e "  --user-role: Custom attribute - the role of the created user in the Hyperledger Fabric network, if applicable."
            exit 1
            ;;
        --org-name)
            ORG_NAME=$2
            shift 2
            ;;
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
        --org-ca-admin-username)
            ORG_CA_ADMIN_USERNAME=$2
            shift 2
            ;;
        --org-ca-admin-password)
            ORG_CA_ADMIN_PASSWORD=$2
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

printf "${C_BLUE_BOLD}\ncreate-user.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=${ORG_NAME}
USER_TYPE=${USER_TYPE}
USER_ROLE=${USER_ROLE:-"NA"}
USER_HOSTNAME=${USER_HOSTNAME}
USER_USERNAME=${USER_USERNAME}
USER_PASSWORD=${USER_PASSWORD}
ORG_CA_ADMIN_USERNAME=${ORG_CA_ADMIN_USERNAME}
ORG_CA_ADMIN_PASSWORD=${ORG_CA_ADMIN_PASSWORD}
TLS_CA_ADMIN_USERNAME=${TLS_CA_ADMIN_USERNAME}
TLS_CA_ADMIN_PASSWORD=${TLS_CA_ADMIN_PASSWORD}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${USER_TYPE} || -z ${USER_ROLE} || -z ${USER_USERNAME} || -z ${USER_PASSWORD} || -z ${USER_HOSTNAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} one or more mandatory arguments have not been provided!${C_RESET}"
    exit 1   
}

[[ ${USER_TYPE} == 'client' || ${USER_TYPE} == 'admin' ]] || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} ${USER_TYPE} is an invalid user type - should be either 'client' or 'admin'!${C_RESET}"
    exit 1
}

kubectl get pod | grep ${ORG_NAME} &> /dev/null || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} ${ORG_NAME} does not exist!${C_RESET}"
    exit 1
}




############################################################## 
# PROCESSING VARIABLES
##############################################################

# in the .env file
KUBERNETES_TLS_CA_HOSTNAME=${ENV_KUBERNETES_TLS_CA_HOSTNAME}

KUBERNETES_ORG_CA_HOSTNAME=ca-${ORG_NAME}




############################################################## 
# GENERATING CERTIFICATES
##############################################################

printf "${C_BLUE_BOLD}\ncreate-user.sh:${C_GRAY_ITALIC} ${USER_USERNAME}@${ORG_NAME} ${C_BLUE}\n > REGISTERING USER AND GENERATING CRYPTO-MATERIALS\n\n${C_RESET}"

. create-crypto.sh \
    --org-name ${ORG_NAME} \
    --org-ca-hostname ${KUBERNETES_ORG_CA_HOSTNAME} \
    --org-ca-admin-username ${ORG_CA_ADMIN_USERNAME} \
    --org-ca-admin-password ${ORG_CA_ADMIN_PASSWORD} \
    --tls-ca-hostname ${KUBERNETES_TLS_CA_HOSTNAME} \
    --tls-ca-admin-username ${TLS_CA_ADMIN_USERNAME} \
    --tls-ca-admin-password ${TLS_CA_ADMIN_PASSWORD}

createUser \
    --user-type ${USER_TYPE} \
    --user-role ${USER_ROLE} \
    --user-username ${USER_USERNAME} \
    --user-password ${USER_PASSWORD} 

createUserTLS \
    --user-type ${USER_TYPE} \
    --user-role ${USER_TOLE} \
    --user-hostname ${USER_HOSTNAME} \
    --user-username ${USER_USERNAME} \
    --user-password ${USER_PASSWORD}