#!/bin/bash

if [ -n "$BPI_SCRIPT_DEBUG" ]; then
  set -x
fi

BPI_CHAIN_WS_URL="ws://${STACK_SVC_FXETH_GETH_1}:8546"
BPI_CHAIN_RPC_URL="http://${STACK_SVC_FXETH_GETH_1}:8545"

if [ -z "$BPI_NITRO_CHAIN_PK" ] || [ -z "$BPI_CHAIN_WS_URL" ] || [ -z "$BPI_CHAIN_RPC_URL" ]; then
  echo "You most set all of BPI_NITRO_CHAIN_PK, BPI_CHAIN_WS_URL and BPI_CHAIN_RPC_URL." 1>&2
  exit 1
fi

BPI_NA_ADDRESS=${BPI_NA_ADDRESS:-0x565541ecdaac2de200e2c5d951ea00ca00f66483}
BPI_VPA_ADDRESS=${BPI_VPA_ADDRESS:-0xb6907879bf59538d58211dd9e3d7d40469867a25}
BPI_CA_ADDRESS=${BPI_CA_ADDRESS:-0xb7bf8e409f2de32dcdc80cb61b78426af6567f3e}

echo "BPI_NA_ADDRESS is set to '$BPI_NA_ADDRESS'"
echo "BPI_VPA_ADDRESS is set to '$BPI_VPA_ADDRESS'"
echo "BPI_CA_ADDRESS is set to '$BPI_CA_ADDRESS'"
export BPI_NA_ADDRESS BPI_VPA_ADDRESS BPI_CA_ADDRESS

echo "Running Nitro node"

if [[ "${BPI_GO_NITRO_WAIT_FOR_CHAIN:-true}" == "true" ]]; then
  # Wait till chain endpoint is available
  retry_interval=5
  while true; do
    code_len=$(curl --location "$BPI_CHAIN_RPC_URL" \
                --header 'Content-Type: application/json' \
                --data "{
                  \"jsonrpc\": \"2.0\",
                  \"id\": 124,
                  \"method\": \"eth_getCode\",
                  \"params\": [\"${BPI_NA_ADDRESS}\", \"latest\"]
                }" | jq '.result' | wc -c)
    if [ $code_len -gt 50 ]    ; then
      echo "Chain endpoint is available"
      break
    fi

    echo "Chain endpoint not yet available, retrying in $retry_interval seconds..."
    sleep $retry_interval
  done
fi

if [[ -z "$BPI_CHAIN_START_BLOCK" ]]; then
  if [[ ! -f "/app/chainstartblock.json" ]]; then
    curl --location "$BPI_CHAIN_RPC_URL" \
    --header 'Content-Type: application/json' \
    --data '{
        "jsonrpc": "2.0",
        "id": 124,
        "method": "eth_blockNumber",
        "params": []
    }' > /app/chainstartblock.json
  fi
  BPI_CHAIN_START_BLOCK=$(printf "%d" `cat /app/chainstartblock.json | jq -r '.result'`)
fi

env
cd /app || die
./nitro \
  -chainurl ${BPI_CHAIN_WS_URL} \
  -msgport ${BPI_NITRO_MSG_PORT} \
  -rpcport ${BPI_NITRO_RPC_PORT} \
  -publicip "0.0.0.0" \
  -pk ${BPI_NITRO_PK:-$BPI_NITRO_CHAIN_PK} \
  -chainpk ${BPI_NITRO_CHAIN_PK} \
  -naaddress ${BPI_NA_ADDRESS} \
  -vpaaddress ${BPI_VPA_ADDRESS} \
  -caaddress ${BPI_CA_ADDRESS} \
  -usedurablestore=${BPI_NITRO_USE_DURABLE_STORE} \
  -durablestorefolder ${BPI_NITRO_DURABLE_STORE_FOLDER} \
  -bootpeers "${BPI_NITRO_BOOT_PEERS}" \
  -tlscertfilepath "${BPI_NITRO_TLS_CERT_FILE_PATH}" \
  -tlskeyfilepath "${BPI_NITRO_TLS_KEY_FILE_PATH}" \
  -chainstartblock $BPI_CHAIN_START_BLOCK
