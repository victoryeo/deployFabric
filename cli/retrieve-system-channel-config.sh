#!/bin/bash

# Exit on first error
set -euo pipefail

ENV_NAME=$1
NAMESPACE=$2
ORG_NAME=$3
SYS_CHANNEL_NAME=$4

ORDERER=orderer0-hlf-ord.${NAMESPACE}.svc.cluster.local:7050
ORDERER_CA=/etc/hyperledger/msps/orderer/cacerts/cert.pem

cd /tmp

cp /etc/hyperledger/config/configtx.yaml /etc/hyperledger/fabric

configtxgen -printOrg ${ORG_NAME} > ${ORG_NAME}.json

jq '.values.MSP.value.config.tls_root_certs = .values.MSP.value.config.root_certs' ${ORG_NAME}.json > tmp.$$.json && mv tmp.$$.json ${ORG_NAME}.json

peer channel fetch config sys_config_block.pb -o ${ORDERER} -c ${SYS_CHANNEL_NAME} --tls --cafile ${ORDERER_CA}

configtxlator proto_decode --input sys_config_block.pb --type common.Block | jq .data.data[0].payload.data.config > ./config.json

jq -s '.[0] * {"channel_group":{"groups":{"Consortiums":{"groups":{"SampleConsortium":{"groups": {"'${ORG_NAME}'":.[1]}}}}}}}' ./config.json ./${ORG_NAME}.json > ./modified_config.json

configtxlator proto_encode --input ./config.json --type common.Config --output ./config.pb

configtxlator proto_encode --input ./modified_config.json --type common.Config --output ./modified_config.pb

configtxlator compute_update --channel_id ${SYS_CHANNEL_NAME} --original ./config.pb --updated ./modified_config.pb --output ./${ORG_NAME}_update.pb

configtxlator proto_decode --input ./${ORG_NAME}_update.pb --type common.ConfigUpdate | jq . > ./${ORG_NAME}_update.json

echo '{"payload":{"header":{"channel_header":{"channel_id":"'${SYS_CHANNEL_NAME}'", "type":2}},"data":{"config_update":'$(cat ./${ORG_NAME}_update.json)'}}}' | jq . > ./${ORG_NAME}_update_in_envelope.json

configtxlator proto_encode --input ./${ORG_NAME}_update_in_envelope.json --type common.Envelope --output ./${ORG_NAME}_update_in_envelope.pb

peer channel update -o ${ORDERER} -c ${SYS_CHANNEL_NAME} -f ./${ORG_NAME}_update_in_envelope.pb \
  --tls --cafile ${ORDERER_CA}