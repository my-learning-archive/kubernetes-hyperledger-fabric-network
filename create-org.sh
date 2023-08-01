#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,org-name:,org-ca-admin-username:,org-ca-admin-password:,tls-ca-admin-username:,tls-ca-admin-password:,peer-username:,peer-password:,couchdb-username:,couchdb-password:,channel-name:,channel-org-name: -- "$@")
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
            echo -e "  --org-name: The name of the created organization."
            echo -e "  --org-ca-admin-username: The username of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --org-ca-admin-password: The password of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --tls-ca-admin-username: The username of the TLS CA admin, for the generation of TLS certificates."
            echo -e "  --tls-ca-admin-password: The password of TLS CA admin, for the generation of TLS certificates."
            echo -e "\nOptional flags:"
            echo -e "  --peer-username: A custom username for the entity of the anchor peer of the created organization to be registered in the organizational and TLS CAs - if not defined, it is set to default."
            echo -e "  --peer-password: A custom password for the entity of the anchor peer of the created organization to be registered in the organizational and TLS CAs - if not defined, it is set to default."
            echo -e "  --couchdb-username: A custom admin username for the CouchDB instance attached to the anchor peer of the created organization - if not defined, it is set to default."
            echo -e "  --couchdb-password: A custom admin password for the CouchDB instance attached to the anchor peer of the created organization - if not defined, it is set to default."
            echo -e "  --channel_name: The name of a channel the created organization should join, upon creation."
            echo -e "  --channel_org_name: The name of one Hyperledger Fabric organization in the channel the created organization should join, upon creation - this is mandatory if the --channel-name argument has been specified."
            exit 1
            ;;
        --org-name)
            ORG_NAME=$2
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
        --peer-username)
            PEER_USERNAME=$2
            shift 2
            ;;
        --peer-password)
            PEER_PASSWORD=$2
            shift 2
            ;;
        --couchdb-username)
            COUCHDB_USERNAME=$2
            shift 2
            ;;
        --couchdb-password)
            COUCHDB_PASSWORD=$2
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

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=${ORG_NAME}
ORG_CA_ADMIN_USERNAME=${ORG_CA_ADMIN_USERNAME}
ORG_CA_ADMIN_PASSWORD=${ORG_CA_ADMIN_PASSWORD}
TLS_CA_ADMIN_USERNAME=${TLS_CA_ADMIN_USERNAME}
TLS_CA_ADMIN_PASSWORD=${TLS_CA_ADMIN_PASSWORD}
PEER_USERNAME=${PEER_USERNAME:-"peer0-"${ORG_NAME}"-un"}
PEER_PASSWORD=${PEER_PASSWORD:-"peer0-"${ORG_NAME}"-pw"}
COUCHDB_USERNAME=${COUCHDB_USERNAME:-"couchdb-peer0-"${ORG_NAME}"-un"}
COUCHDB_PASSWORD=${COUCHDB_PASSWORD:-"couchdb-peer0-"${ORG_NAME}"-pw"}
CHANNEL_NAME=${CHANNEL_NAME:-"NA"}
CHANNEL_ORG_NAME=${CHANNEL_ORG_NAME:-"NA"}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} || -z ${PEER_USERNAME} || -z ${PEER_PASSWORD} || -z ${COUCHDB_USERNAME} || -z ${COUCHDB_PASSWORD} || -z ${CHANNEL_NAME} || -z ${CHANNEL_ORG_NAME} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more mandatory arguments have not been provided. Exiting. ${C_RESET}"
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
KUBERNETES_TLS_CA_HOSTNAME=${ENV_KUBERNETES_TLS_CA_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')




############################################################## 
# GENERATING CERTIFICATES
##############################################################

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > GENERATING CRYPTO-MATERIALS\n\n${C_RESET}"

mkdir -p ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/

cat << EOF > ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/ca-${ORG_NAME}.yaml
kind: Service
apiVersion: v1
metadata:
  name: ca-${ORG_NAME}
spec:
  selector:
    app: blockchain
    role: ca-${ORG_NAME}
  ports:
    - name: tcp-7054
      port: 7054
      protocol: TCP

---

kind: Deployment
apiVersion: apps/v1
metadata:
  name: ca-${ORG_NAME}
  labels:
    app: blockchain
    role: ca-${ORG_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockchain
      role: ca-${ORG_NAME}
  template:
    metadata:
      labels:
        app: blockchain
        role: ca-${ORG_NAME}
    spec:
      volumes:
        - name: nfs
          persistentVolumeClaim:
            claimName: nfs
      containers:
        - name: ca-${ORG_NAME}
          image: hyperledger/fabric-ca:1.4.9
          args:
            - sh
            - -c
            - fabric-ca-server start -b admin:adminpw -d --csr.hosts 'ca-${ORG_NAME}'  --csr.cn 'ca-${ORG_NAME}'
          env:
            - name: FABRIC_CA_HOME
              value: /etc/hyperledger/fabric-ca-server
            - name: FABRIC_CA_SERVER_CA_CERTFILE
              value: /etc/hyperledger/fabric-ca-server-config/ca-${ORG_NAME}-cert.pem
            - name: FABRIC_CA_SERVER_CA_KEYFILE
              value: /etc/hyperledger/fabric-ca-server-config/priv_sk
            - name: FABRIC_CA_SERVER_CA_NAME
              value: ca-${ORG_NAME}
            - name: FABRIC_CA_SERVER_TLS_ENABLED
              value: "true"
          ports:
            - containerPort: 7054
          volumeMounts:
            - name: nfs
              mountPath: /etc/hyperledger/fabric-ca-server-config
              subPath: crypto-config/peerOrganizations/${ORG_NAME}/ca/
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh","-c","rm -rf /etc/hyperledger/fabric-ca-server-config/*"]
EOF

kubectl apply -f ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/ca-${ORG_NAME}.yaml

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

KUBERNETES_ORG_CA_HOSTNAME=ca-${ORG_NAME}

source create-crypto.sh \
    --org-name ${ORG_NAME} \
    --org-ca-hostname ${KUBERNETES_ORG_CA_HOSTNAME} \
    --org-ca-admin-username ${ORG_CA_ADMIN_USERNAME} \
    --org-ca-admin-password ${ORG_CA_ADMIN_PASSWORD} \
    --tls-ca-hostname ${KUBERNETES_TLS_CA_HOSTNAME} \
    --tls-ca-admin-username ${TLS_CA_ADMIN_USERNAME} \
    --tls-ca-admin-password ${TLS_CA_ADMIN_PASSWORD} || exit 1

createOrg || exit 1

createEntity \
    --entity-name peer0 \
    --entity-username ${PEER_USERNAME} \
    --entity-password ${PEER_PASSWORD} || exit 1

createEntityTLS \
    --entity-name peer0 \
    --entity-username ${PEER_USERNAME} \
    --entity-password ${PEER_PASSWORD} || exit 1




############################################################## 
# GENERATING ORGANIZATION DEFINITIONS
##############################################################

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > GENERATING ORGANIZATION DEFINITIONS\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

mkdir -p ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'

cat << EOF > ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'/configtx.yaml
Organizations:
    - &'${ORG_NAME^}'
      Name: '${ORG_NAME^}'MSP
      ID: '${ORG_NAME^}'MSP
      MSPDir: ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/msp
      Policies:
          Readers:
              Type: Signature
              Rule: "OR('"'"''${ORG_NAME^}'MSP.admin'"'"', '"'"''${ORG_NAME^}'MSP.peer'"'"', '"'"''${ORG_NAME^}'MSP.client'"'"')"
          Writers:
              Type: Signature
              Rule: "OR('"'"''${ORG_NAME^}'MSP.admin'"'"', '"'"''${ORG_NAME^}'MSP.client'"'"')"
          Admins:
              Type: Signature
              Rule: "OR('"'"''${ORG_NAME^}'MSP.admin'"'"')"
          Endorsement:
              Type: Signature
              Rule: "OR('"'"''${ORG_NAME^}'MSP.peer'"'"')"
      AnchorPeers:
          - Host: peer0-'${ORG_NAME}'
            Port: 7051
EOF

configtxgen \
	-configPath ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'/ \
	-printOrg '${ORG_NAME^}'MSP > ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'/'${ORG_NAME}'-definition.json

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not generate organization definitions. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# STARTING ANCHOR PEER SERVICE
##############################################################

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > STARTING ANCHOR PEER SERVICE\n\n${C_RESET}"

cat << EOF > ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/peer0-${ORG_NAME}.yaml
kind: Service
apiVersion: v1
metadata:
  name: peer0-${ORG_NAME}
spec:
  selector:
    app: blockchain
    role: peer0-${ORG_NAME}
  ports:
    - name: tcp-7051
      port: 7051
      protocol: TCP
    - name: tcp-7053
      port: 7053
      protocol: TCP

---

kind: Deployment
apiVersion: apps/v1
metadata:
  name: peer0-${ORG_NAME}
  labels:
    app: blockchain
    role: peer0-${ORG_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockchain
      role: peer0-${ORG_NAME}
  template:
    metadata:
      labels:
        app: blockchain
        role: peer0-${ORG_NAME}
    spec:
      volumes:
        - name: nfs
          persistentVolumeClaim:
            claimName: nfs
        - name: external-builder-detect
          configMap:
            name: builders-config
            items:
              - key: detect
                path: detect
                mode: 0544
        - name: external-builder-build
          configMap:
            name: builders-config
            items:
              - key: build
                path: build
                mode: 0544
        - name: external-builder-release
          configMap:
            name: builders-config
            items:
              - key: release
                path: release
                mode: 0544
      containers:
        - name: peer0-${ORG_NAME}
          image: hyperledger/fabric-peer:2.4.6
          workingDir: /opt/gopath/src/github.com/hyperledger/fabric
          args:
            - sh
            - -c
            - peer node start
          env:
            - name: CORE_PEER_ID
              value: peer0-${ORG_NAME}
            - name: FABRIC_LOGGING_SPEC
              value: INFO
            - name: CORE_PEER_TLS_ENABLED
              value: 'true'
            - name: CORE_PEER_TLS_CERT_FILE
              value: /etc/hyperledger/fabric/tls/server.crt
            - name: CORE_PEER_TLS_KEY_FILE
              value: /etc/hyperledger/fabric/tls/server.key
            - name: CORE_PEER_TLS_ROOTCERT_FILE
              value: /etc/hyperledger/fabric/tls/ca.crt
            - name: CORE_PEER_TLS_CLIENTAUTHREQUIRED
              value: 'false'
            - name: CORE_PEER_TLS_CLIENTROOTCAS_FILES
              value: /etc/hyperledger/fabric/tls/ca.crt
            - name: CORE_PEER_TLS_CLIENTCERT_FILE
              value: /etc/hyperledger/fabric/tls/server.crt
            - name: CORE_PEER_TLS_CLIENTKEY_FILE
              value: /etc/hyperledger/fabric/tls/server.key
            - name: CORE_PEER_LOCALMSPID
              value: ${ORG_NAME^}MSP            
            - name: CORE_PEER_MSPCONFIGPATH
              value: /etc/hyperledger/fabric/msp/
            - name: CORE_PEER_ADDRESS
              value: peer0-${ORG_NAME}:7051
            - name: CORE_PEER_GOSSIP_EXTERNALENDPOINT
              value: peer0-${ORG_NAME}:7051
            - name: CORE_PEER_CHAINCODELISTENADDRESS
              value: 0.0.0.0:7052
            - name: CORE_LEDGER_STATE_STATEDATABASE
              value: CouchDB
            - name: CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS
              value: localhost:5984 # because couchDB is running in the same pod
            - name: CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME
              value: ${COUCHDB_USERNAME}
            - name: CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD
              value: ${COUCHDB_PASSWORD}
            - name: CORE_LEDGER_STATE_COUCHDBCONFIG_MAXRETRIESONSTARTUP
              value: '30'
            - name: CORE_CHAINCODE_EXTERNALBUILDERS
              value: '[{name: external-builder, path: /builders/external}]'
          ports:
            - containerPort: 7051
            - containerPort: 7053
          volumeMounts:
            - name: nfs
              mountPath: /etc/hyperledger/fabric/msp
              subPath: crypto-config/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/msp
            - name: nfs
              mountPath: /etc/hyperledger/fabric/tls
              subPath: crypto-config/peerOrganizations/${ORG_NAME}/peers/peer0-${ORG_NAME}/tls
            - name: external-builder-detect
              mountPath: /builders/external/bin/detect
              subPath: detect
            - name: external-builder-build
              mountPath: /builders/external/bin/build
              subPath: build
            - name: external-builder-release
              mountPath: /builders/external/bin/release
              subPath: release
        - name: couchdb-peer0-${ORG_NAME}
          image: hyperledger/fabric-couchdb
          env:
            - name: COUCHDB_USER
              value: ${COUCHDB_USERNAME}
            - name: COUCHDB_PASSWORD
              value: ${COUCHDB_PASSWORD}
          ports:
            - containerPort: 5984
EOF

kubectl apply -f ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/peer0-${ORG_NAME}.yaml

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
# JOINING ORGANIZATION TO CONSORTIUM
##############################################################

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > JOINING ORGANIZATION TO CONSORTIUM\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID=OrdererMSP
export CORE_PEER_ADDRESS=orderer0-orderers:7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/ordererOrganizations/orderers/users/orderersadmin@orderers/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/ordererOrganizations/orderers/orderers/orderer0-orderers/tls/ca.crt

cd ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'/

BLOCK_FETCHED_CONFIG_PB=blockFetchedConfig-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.pb
CONFIG_BLOCK_JSON=configBlock-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.json
CONFIG_BLOCK_PB=configBlock-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.pb
CONFIG_CHANGES_JSON=configChanges-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.json
CONFIG_CHANGES_PB=configChanges-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.pb
CONFIG_PROPOSAL_JSON=configProposal-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.json
CONFIG_PROPOSAL_PB=configProposal-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.pb
SUBMIT_READY_JSON=submitReady-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.json
SUBMIT_READY_PB=submitReady-${SYS_CHANNEL_NAME}-'${ORG_NAME}'.pb

peer channel fetch config ${BLOCK_FETCHED_CONFIG_PB} \
    -o ${ORDERER_ENDPOINT} \
    -c ${SYS_CHANNEL_NAME} \
    --tls --cafile ${ORDERER_TLS_CA}

configtxlator proto_decode \
	--input ${BLOCK_FETCHED_CONFIG_PB} \
	--type common.Block | jq .data.data[0].payload.data.config > ${CONFIG_BLOCK_JSON}

jq -s '"'"'.[0] * {"channel_group":{"groups":{"Consortiums":{"groups":{"SampleConsortium":{"groups":{"'${ORG_NAME^}'MSP":.[1]}}}}}}}'"'"' ${CONFIG_BLOCK_JSON} '${ORG_NAME}'-definition.json > ${CONFIG_CHANGES_JSON}

configtxlator proto_encode \
	--input ${CONFIG_BLOCK_JSON} \
	--type common.Config \
	--output ${CONFIG_BLOCK_PB}

configtxlator proto_encode \
	--input ${CONFIG_CHANGES_JSON} \
	--type common.Config \
	--output ${CONFIG_CHANGES_PB}

configtxlator compute_update \
	--channel_id ${SYS_CHANNEL_NAME} \
	--original ${CONFIG_BLOCK_PB} \
	--updated ${CONFIG_CHANGES_PB} \
	--output ${CONFIG_PROPOSAL_PB}

configtxlator proto_decode \
	--input ${CONFIG_PROPOSAL_PB} \
	--type common.ConfigUpdate | jq . > ${CONFIG_PROPOSAL_JSON}

echo '"'"'{"payload":{"header":{"channel_header":{"channel_id":"'"'"'${SYS_CHANNEL_NAME}'"'"'","type":2}},"data":{"config_update":'"'"'$(cat ${CONFIG_PROPOSAL_JSON})'"'"'}}}'"'"' | jq . > ${SUBMIT_READY_JSON}

configtxlator proto_encode \
	--input ${SUBMIT_READY_JSON} \
	--type common.Envelope \
	--output ${SUBMIT_READY_PB}

peer channel update \
	-o ${ORDERER_ENDPOINT} \
	-c ${SYS_CHANNEL_NAME} \
	-f ${SUBMIT_READY_PB} \
	--tls --cafile ${ORDERER_TLS_CA}

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not join organization to the system channel. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# JOINING ORGANIZATION TO APPLICATION CHANNEL
##############################################################

[[ ${CHANNEL_NAME} == "NA" ]] || {

	printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > JOINING ORGANIZATION TO APPLICATION CHANNEL\n\n${C_RESET}"

	source join-org-to-channel.sh \
		--org-name ${ORG_NAME} \
		--channel-name ${CHANNEL_NAME} \
		--channel-org-name ${CHANNEL_ORG_NAME} || exit 1
}




############################################################## 
# CONFIGURING DISCOVERY SERVICE
##############################################################

printf "${C_BLUE_BOLD}\ncreate-org.sh:${C_GRAY_ITALIC} ${ORG_NAME} ${C_BLUE}\n > CONFIGURING DISCOVERY SERVICE\n\n${C_RESET}"

kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

discover \
	--configFile ${CONFIGTX_HOME}/peerOrganizations/'${ORG_NAME}'/discovery-conf-'${ORG_NAME}'.yaml \
	--tlsCert ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.crt \
	--tlsKey ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/server.key \
	--peerTLSCA ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/peer0-'${ORG_NAME}'/tls/ca.crt \
	--userKey $(ls ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/keystore/*) \
	--userCert ${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp/signcerts/cert.pem \
	--MSP '${ORG_NAME^}'MSP saveConfig

###################### INTERNAL COMMAND ######################' || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not configure discovery service. Exiting. ${C_RESET}"
    exit 1
}
