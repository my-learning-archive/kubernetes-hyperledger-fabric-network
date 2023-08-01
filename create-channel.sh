#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,channel-name:,orgs-list: -- "$@")
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
            echo -e "  --channel-name: The name of the created channel."
            echo -e "  --orgs-list: The names, separated by commas, of Hyperledger Fabric organizations that will belong to the created channel."
            exit 1
            ;;
        --channel-name)
            CHANNEL_NAME=$2
            shift 2
            ;;
        --orgs-list)
            ORGS_LIST=$2
            shift 2
            ;;
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ncreate-channel.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
CHANNEL_NAME=${CHANNEL_NAME}
ORGS_LIST=${ORGS_LIST}
{ set +x; } 2>/dev/null

[[ -z ${CHANNEL_NAME} || -z ${ORGS_LIST} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more mandatory arguments have not been provided. Exiting. ${C_RESET}"
    exit 1   
}

for ORG_NAME in ${ORGS_LIST//,/ }; do
    kubectl get deploy | grep -i peer0-${ORG_NAME} &> /dev/null || {
        >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Inexistent Hyperledger Fabric organization - ${ORG_NAME}. Exiting. ${C_RESET}"
        exit 1
    }
done




############################################################## 
# PROCESSING VARIABLES
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')




############################################################## 
# CREATING CONFIG FILES - configtx.yaml
##############################################################

printf "${C_BLUE_BOLD}\ncreate-channel.sh:${C_GRAY_ITALIC} ${CHANNEL_NAME} ${C_BLUE}\n > CREATING configtx.yaml\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

ORGS_LIST=$(echo '${ORGS_LIST}' | sed "s/,/ /g")

mkdir -p ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'

cat << EOF > ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
Organizations:
    - &OrdererOrg
        Name: OrdererOrg
        ID: OrdererMSP
        MSPDir: ${CRYPTO_HOME}/ordererOrganizations/orderers/msp
        Policies:
            Readers:
                Type: Signature
                Rule: "OR('OrdererMSP.member')"
            Writers:
                Type: Signature
                Rule: "OR('OrdererMSP.member')"
            Admins:
                Type: Signature
                Rule: "OR('OrdererMSP.admin')"
        OrdererEndpoints:
            - orderer0-orderers:7050
            - orderer1-orderers:7050
            - orderer2-orderers:7050
EOF

for ORG_NAME in ${ORGS_LIST}; do
cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
    - &${ORG_NAME^}
        Name: ${ORG_NAME^}MSP
        ID: ${ORG_NAME^}MSP
        MSPDir: ${CRYPTO_HOME}/peerOrganizations/${ORG_NAME}/msp
        Policies:
            Readers:
                Type: Signature
                Rule: "OR('"'"'${ORG_NAME^}MSP.admin'"'"', '"'"'${ORG_NAME^}MSP.peer'"'"', '"'"'${ORG_NAME^}MSP.client'"'"')"
            Writers:
                Type: Signature
                Rule: "OR('"'"'${ORG_NAME^}MSP.admin'"'"', '"'"'${ORG_NAME^}MSP.client'"'"')"
            Admins:
                Type: Signature
                Rule: "OR('"'"'${ORG_NAME^}MSP.admin'"'"')"
            Endorsement:
                Type: Signature
                Rule: "OR('"'"'${ORG_NAME^}MSP.peer'"'"')"
        AnchorPeers:
            - Host: peer0-${ORG_NAME}
              Port: 7051
EOF
done 

cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
Capabilities:
    Channel: &ChannelCapabilities
        V2_0: true
    Orderer: &OrdererCapabilities
        V2_0: true
    Application: &ApplicationCapabilities
        V2_0: true
Application: &ApplicationDefaults
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
        LifecycleEndorsement:
            Type: ImplicitMeta
            Rule: "MAJORITY Endorsement"
        Endorsement:
            Type: ImplicitMeta
            Rule: "MAJORITY Endorsement"
    Capabilities:
        <<: *ApplicationCapabilities
Orderer: &OrdererDefaults
    OrdererType: etcdraft
    Addresses:
        - orderer0-orderers:7050
        - orderer1-orderers:7050
        - orderer2-orderers:7050
    EtcdRaft:
        Consenters:
        - Host: orderer0-orderers
          Port: 7050
          ClientTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.crt
          ServerTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.crt
        - Host: orderer1-orderers
          Port: 7050
          ClientTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer1-orderers/tls/server.crt
          ServerTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer1-orderers/tls/server.crt
        - Host: orderer2-orderers
          Port: 7050
          ClientTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer2-orderers/tls/server.crt
          ServerTLSCert: ${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer2-orderers/tls/server.crt
    BatchTimeout: 2s
    BatchSize:
        MaxMessageCount: 10
        AbsoluteMaxBytes: 99 MB
        PreferredMaxBytes: 512 KB
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
        BlockValidation:
            Type: ImplicitMeta
            Rule: "ANY Writers"
Channel: &ChannelDefaults
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
    Capabilities:
        <<: *ChannelCapabilities
Profiles:
    OrgOrdererGenesis:
        <<: *ChannelDefaults
        Orderer:
            <<: *OrdererDefaults
            Organizations:
                - *OrdererOrg
            Capabilities:
                <<: *OrdererCapabilities
        Consortiums:
            SampleConsortium:
                Organizations:
EOF

for ORG_NAME in ${ORGS_LIST}; do
cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
                    - *${ORG_NAME^}
EOF
done

cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
    OrgChannel:
        Consortium: SampleConsortium
        <<: *ChannelDefaults
        Application:
            <<: *ApplicationDefaults
            Organizations:
EOF

for ORG_NAME in ${ORGS_LIST}; do
cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
                - *${ORG_NAME^}
EOF
done

cat << EOF >> ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/configtx.yaml
            Capabilities:
                <<: *ApplicationCapabilities
EOF

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not create configuration file. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# GENERATING APPLICATION CHANNEL CREATION TRANSACTION 
##############################################################

printf "${C_BLUE_BOLD}\ncreate-channel.sh:${C_GRAY_ITALIC} ${CHANNEL_NAME} ${C_BLUE}\n > GENERATING APPLICATION CHANNEL CREATION TRANSACTION\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

configtxgen \
    -configPath ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/ \
    -profile OrgChannel \
    -channelID '${CHANNEL_NAME}' \
    -outputCreateChannelTx ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/'${CHANNEL_NAME}'.tx

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not generate application channel creation transaction. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# CREATING APPLICATION CHANNEL 
##############################################################

printf "${C_BLUE_BOLD}\ncreate-channel.sh:${C_GRAY_ITALIC} ${CHANNEL_NAME} ${C_BLUE}\n > CREATING APPLICATION CHANNEL\n\n${C_RESET}"

ORG_NAME=$(echo ${ORGS_LIST//,/ }| awk '{print $1;}')

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

peer channel create \
    -o ${ORDERER_ENDPOINT} \
    -c '${CHANNEL_NAME}' \
    -f ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/'${CHANNEL_NAME}'.tx \
    --tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not create application channel. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# JOINING PEERS TO APPLICATION CHANNEL 
##############################################################

printf "${C_BLUE_BOLD}\ncreate-channel.sh:${C_GRAY_ITALIC} ${CHANNEL_NAME} ${C_BLUE}\n > JOINING PEERS TO APPLICATION CHANNEL\n\n${C_RESET}"

for ORG_NAME in ${ORGS_LIST//,/ }; do

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
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_HOSTNAME}'/tls/ca.crt

peer channel fetch oldest '${CHANNEL_NAME}'.block \
    -o ${ORDERER_ENDPOINT} \
    -c '${CHANNEL_NAME}' \
    --tls --cafile ${ORDERER_TLS_CA}

peer channel join \
    -b '${CHANNEL_NAME}'.block

###################### INTERNAL COMMAND ######################' || {
            >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not join peer to application channel. Exiting. ${C_RESET}"
            exit 1
        }

    done
done