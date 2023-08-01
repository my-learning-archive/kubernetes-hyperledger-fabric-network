#!/bin/bash

set -o allexport && source .env && set +o allexport
SCRIPT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )




############################################################## 
# INPUT VARIABLES
##############################################################

VALID_ARGS=$(getopt -o h\0 --long help,org-name:,org-ca-admin-username:,org-ca-admin-password:,tls-ca-admin-username:,tls-ca-admin-password:,peer-username:,peer-password:,couchdb-username:,couchdb-password: -- "$@")
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
            echo -e "  --org-name: The name of the Hyperledger Fabric organization the created peer will belong to."
            echo -e "  --org-ca-admin-username: The username of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --org-ca-admin-password: The password of the Hyperledger Fabric organizational CA admin, for the generation of MSP certificates."
            echo -e "  --tls-ca-admin-username: The username of the TLS CA admin, for the generation of TLS certificates."
            echo -e "  --tls-ca-admin-password: The password of TLS CA admin, for the generation of TLS certificates."
            echo -e "\nOptional flags:"
            echo -e "(In the following flags, the '%' character is substituted by the cardinality of the created peer, discovered internally.)"
            echo -e "  --peer-username: A custom username for the entity of the created peer to be registered in the organizational and TLS CAs - if not defined, it is set to default."
            echo -e "  --peer-password: A custom password for the entity of the created peer to be registered in the organizational and TLS CAs - if not defined, it is set to default."
            echo -e "  --couchdb-username: A custom admin username for the CouchDB instance attached to the created peer - if not defined, it is set to default."
            echo -e "  --couchdb-password: A custom admin password for the CouchDB instance attached to the created peer - if not defined, it is set to default."
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
        --) shift; 
            break 
            ;;
    esac
done

printf "${C_BLUE_BOLD}\ncreate-peer.sh:${C_BLUE}\n > DEFINING INPUT VARIABLE\n\n${C_RESET}"

set -x
ORG_NAME=${ORG_NAME}
ORG_CA_ADMIN_USERNAME=${ORG_CA_ADMIN_USERNAME}
ORG_CA_ADMIN_PASSWORD=${ORG_CA_ADMIN_PASSWORD}
TLS_CA_ADMIN_USERNAME=${TLS_CA_ADMIN_USERNAME}
TLS_CA_ADMIN_PASSWORD=${TLS_CA_ADMIN_PASSWORD}
PEER_USERNAME=${PEER_USERNAME:-"peer%-"${ORG_NAME}"-un"}
PEER_PASSWORD=${PEER_PASSWORD:-"peer%-"${ORG_NAME}"-pw"}
COUCHDB_USERNAME=${COUCHDB_USERNAME:-"couchdb-peer%-"${ORG_NAME}"-un"}
COUCHDB_PASSWORD=${COUCHDB_PASSWORD:-"couchdb-peer%-"${ORG_NAME}"-pw"}
{ set +x; } 2>/dev/null

[[ -z ${ORG_NAME} || -z ${ORG_CA_ADMIN_USERNAME} || -z ${ORG_CA_ADMIN_PASSWORD} || -z ${TLS_CA_ADMIN_USERNAME} || -z ${TLS_CA_ADMIN_PASSWORD} || -z ${PEER_USERNAME} || -z ${PEER_PASSWORD} || -z ${COUCHDB_USERNAME} || -z ${COUCHDB_PASSWORD} ]] && {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} One or more mandatory arguments have not been provided. Exiting. ${C_RESET}"
    exit 1   
}

kubectl get deploy | grep -i peer0-${ORG_NAME} &> /dev/null || {
    >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Inexistent Hyperledger Fabric organization - ${ORG_NAME}. Exiting. ${C_RESET}"
    exit 1
}




############################################################## 
# PROCESSING VARIABLES
##############################################################

# in the .env file
KUBERNETES_CLI_HOSTNAME=${ENV_KUBERNETES_CLI_HOSTNAME}
KUBERNETES_TLS_CA_HOSTNAME=${ENV_KUBERNETES_TLS_CA_HOSTNAME}

KUBERNETES_CLI_POD_NAME=$(kubectl get pods | grep ^${KUBERNETES_CLI_HOSTNAME}-* | awk '{print $1}')

PEER_NUMBER=$(kubectl get service | awk '{print $1}' | grep ^peer | grep ${ORG_NAME} | wc -l)
PEER_NAME=peer${PEER_NUMBER}

PEER_USERNAME=$(echo ${PEER_USERNAME} | sed "s/%/${PEER_NUMBER}/g")
PEER_PASSWORD=$(echo ${PEER_PASSWORD} | sed "s/%/${PEER_NUMBER}/g")
COUCHDB_USERNAME=$(echo ${COUCHDB_USERNAME} | sed "s/%/${PEER_NUMBER}/g")
COUCHDB_PASSWORD=$(echo ${COUCHDB_PASSWORD} | sed "s/%/${PEER_NUMBER}/g")

ORG_CHANNELS_LIST=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
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

peer channel list | sed 1d

###################### INTERNAL COMMAND ######################' | tail -n +2 | sed 's/\r$//' | sort)




############################################################## 
# GENERATING CERTIFICATES
##############################################################

printf "${C_BLUE_BOLD}\ncreate-peer.sh:${C_GRAY_ITALIC} ${PEER_NAME}-${ORG_NAME} ${C_BLUE}\n > GENERATING CRYPTO-MATERIALS\n\n${C_RESET}"

KUBERNETES_ORG_CA_HOSTNAME=ca-${ORG_NAME}

source create-crypto.sh \
    --org-name ${ORG_NAME} \
    --org-ca-hostname ${KUBERNETES_ORG_CA_HOSTNAME} \
    --org-ca-admin-username ${ORG_CA_ADMIN_USERNAME} \
    --org-ca-admin-password ${ORG_CA_ADMIN_PASSWORD} \
    --tls-ca-hostname ${KUBERNETES_TLS_CA_HOSTNAME} \
    --tls-ca-admin-username ${TLS_CA_ADMIN_USERNAME} \
    --tls-ca-admin-password ${TLS_CA_ADMIN_PASSWORD} || exit 1

createEntity \
    --entity-name ${PEER_NAME} \
    --entity-username ${PEER_USERNAME} \
    --entity-password ${PEER_PASSWORD} || exit 1

createEntityTLS \
    --entity-name ${PEER_NAME} \
    --entity-username ${PEER_USERNAME} \
    --entity-password ${PEER_PASSWORD} || exit 1




############################################################## 
# STARTING PEER SERVICE
##############################################################

printf "${C_BLUE_BOLD}\ncreate-peer.sh:${C_GRAY_ITALIC} ${PEER_NAME}-${ORG_NAME} ${C_BLUE}\n > STARTING PEER SERVICE\n\n${C_RESET}"

mkdir -p ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/

cat << EOF > ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${PEER_NAME}-${ORG_NAME}.yaml
kind: Service
apiVersion: v1
metadata:
  name: ${PEER_NAME}-${ORG_NAME}
spec:
  selector:
    app: blockchain
    role: ${PEER_NAME}-${ORG_NAME}
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
  name: ${PEER_NAME}-${ORG_NAME}
  labels:
    app: blockchain
    role: ${PEER_NAME}-${ORG_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blockchain
      role: ${PEER_NAME}-${ORG_NAME}
  template:
    metadata:
      labels:
        app: blockchain
        role: ${PEER_NAME}-${ORG_NAME}
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
        - name: ${PEER_NAME}-${ORG_NAME}
          image: hyperledger/fabric-peer:2.4.6
          workingDir: /opt/gopath/src/github.com/hyperledger/fabric
          args:
            - sh
            - -c
            - peer node start
          env:
            - name: CORE_PEER_ID
              value: ${PEER_NAME}-${ORG_NAME}
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
              value: Org1MSP            
            - name: CORE_PEER_MSPCONFIGPATH
              value: /etc/hyperledger/fabric/msp/
            - name: CORE_PEER_ADDRESS
              value: ${PEER_NAME}-${ORG_NAME}:7051
            - name: CORE_PEER_GOSSIP_EXTERNALENDPOINT
              value: ${PEER_NAME}-${ORG_NAME}:7051
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
              subPath: crypto-config/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}-${ORG_NAME}/msp
            - name: nfs
              mountPath: /etc/hyperledger/fabric/tls
              subPath: crypto-config/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}-${ORG_NAME}/tls
            - name: external-builder-detect
              mountPath: /builders/external/bin/detect
              subPath: detect
            - name: external-builder-build
              mountPath: /builders/external/bin/build
              subPath: build
            - name: external-builder-release
              mountPath: /builders/external/bin/release
              subPath: release
        - name: couchdb-${PEER_NAME}-${ORG_NAME}
          image: hyperledger/fabric-couchdb
          env:
            - name: COUCHDB_USER
              value: ${COUCHDB_USERNAME}
            - name: COUCHDB_PASSWORD
              value: ${COUCHDB_PASSWORD}
          ports:
            - containerPort: 5984
EOF

kubectl apply -f ${SCRIPT}/kubernetes-manifests/expand/${ORG_NAME}/${PEER_NAME}-${ORG_NAME}.yaml

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
# JOINING PEER TO APPLICATION CHANNELS
##############################################################

printf "${C_BLUE_BOLD}\ncreate-peer.sh:${C_GRAY_ITALIC} ${PEER_NAME}-${ORG_NAME} ${C_BLUE}\n > JOINING PEER TO APPLICATION CHANNELS\n\n${C_RESET}"

for CHANNEL_NAME in ${ORG_CHANNELS_LIST}; do

	echo -e "${C_BLUE}\nJoining peer to ${CHANNEL_NAME} application channel ...${C_RESET}"

	kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
export CORE_PEER_ADDRESS='${PEER_NAME}'-'${ORG_NAME}':7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/ca.crt

peer channel fetch oldest ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/'${CHANNEL_NAME}'.block \
	-o ${ORDERER_ENDPOINT} \
	-c '${CHANNEL_NAME}' \
	--tls --cafile ${ORDERER_TLS_CA}

for i in {1..10}; do

	peer channel join \
		-b ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/'${CHANNEL_NAME}'.block

	if [ $? -eq 0 ]; then
		break
	fi
	if [ $i -eq 10 ]; then
		exit 1
	fi
	sleep 10
done

###################### INTERNAL COMMAND ######################' || {
		>&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not join peer to application channel. Exiting. ${C_RESET}"
		exit 1
	}

done



############################################################## 
# INSTALLING CHAINCODES ON PEER
##############################################################

printf "${C_BLUE_BOLD}\ncreate-peer.sh:${C_GRAY_ITALIC} ${PEER_NAME}-${ORG_NAME} ${C_BLUE}\n > INSTALLING CHAINCODES ON PEER\n\n${C_RESET}"

for CHANNEL_NAME in ${ORG_CHANNELS_LIST}; do

	CHANNEL_CHAINCODES_LIST=$(kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
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

peer lifecycle chaincode querycommitted --channelID '${CHANNEL_NAME}'

###################### INTERNAL COMMAND ######################' | tail -n +2 | tr -d "," | awk '{print $2}')
	
	for CHAINCODE_LABEL in ${CHANNEL_CHAINCODES_LIST}; do

		echo -e "${C_BLUE}\nInstalling ${CHAINCODE_LABEL} chaincode ...${C_RESET}"

		kubectl exec -it ${KUBERNETES_CLI_POD_NAME} -- bash -c '
###################### INTERNAL COMMAND ######################

export CORE_PEER_LOCALMSPID='${ORG_NAME^}'MSP
export CORE_PEER_ADDRESS='${PEER_NAME}'-'${ORG_NAME}':7051
export CORE_PEER_MSPCONFIGPATH=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/users/'${ORG_NAME}'admin@'${ORG_NAME}'/msp
export CORE_PEER_TLS_CERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_KEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_ROOTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/ca.crt
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.crt
export CORE_PEER_TLS_CLIENTCERT_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/server.key
export CORE_PEER_TLS_CLIENTKEY_FILE=${CRYPTO_HOME}/peerOrganizations/'${ORG_NAME}'/peers/'${PEER_NAME}'-'${ORG_NAME}'/tls/ca.crt

peer lifecycle chaincode install ${CONFIGTX_HOME}/applicationChannels/'${CHANNEL_NAME}'/chaincodes/'${CHAINCODE_LABEL}'/'${CHAINCODE_LABEL}'-'${ORG_NAME}'.tgz

###################### INTERNAL COMMAND ######################' || {
            >&2 echo -e "${C_RED_BOLD}ERROR:${C_RED} Could not install chaincode on peer. Exiting. ${C_RESET}"
            exit 1
        }
	
	done
done