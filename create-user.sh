#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

printf "${C_BLUE_BOLD}\ncreate-user.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=$1
USER_TYPE=$2
USER_USERNAME=$3
USER_PASSWORD=$4
USER_HOSTNAME=$5
ORG_CA_ADMIN_USERNAME=$6
ORG_CA_ADMIN_PASSWORD=$7
TLS_CA_ADMIN_USERNAME=$8
TLS_CA_ADMIN_PASSWORD=$9
USER_ROLE=${10:-"NA"}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${USER_TYPE} || -z ${USER_USERNAME} || -z ${USER_PASSWORD} || -z ${USER_HOSTNAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} || -z ${USER_ROLE} ]] && {
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

. create-crypto.sh ${ORG_NAME} ${KUBERNETES_ORG_CA_HOSTNAME} ${ORG_CA_ADMIN_USERNAME} ${ORG_CA_ADMIN_PASSWORD} ${KUBERNETES_TLS_CA_HOSTNAME} ${TLS_CA_ADMIN_USERNAME} ${TLS_CA_ADMIN_PASSWORD}

createUser ${USER_TYPE} ${USER_USERNAME} ${USER_PASSWORD} ${USER_ROLE}
createUserTLS ${USER_TYPE} ${USER_USERNAME} ${USER_PASSWORD} ${USER_HOSTNAME} ${USER_ROLE}