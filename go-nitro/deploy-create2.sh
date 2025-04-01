#!/usr/bin/env bash
# Run this script once after bringing up gitea in docker compose
# TODO: add a check to detect that gitea has not fully initialized yet (no user relation error)

if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

if [[ -f "${BPI_SO_DEPLOYMENT_DIR}/.init_complete" ]]; then
  echo "Initialization complete (if this is wrong, remove ${BPI_SO_DEPLOYMENT_DIR}/.init_complete and restart the stack)."
  exit 0
fi

EXEC_CMD="stack deployment --dir ${BPI_SO_DEPLOYMENT_DIR} exec go-nitro-bootnode"

# Wait till ETH RPC endpoint is available with block number > 1
retry_interval=5
while true; do
  block_number_hex=$( $EXEC_CMD "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://\${STACK_SVC_FXETH_GETH_1}:8545 | jq -r '.result'")

  # Check if the request call was successful
  if [ $? -ne 0 ] || [ -z "$block_number_hex" ] || [[ $block_number_hex == *"rror"* ]]; then
    echo "RPC endpoint not yet available, retrying in $retry_interval seconds..."
    sleep $retry_interval
    continue
  fi

  # Convert hex to decimal
  block_number_dec=$(printf %u ${block_number_hex})

  # Check if block number is > 1 to avoid failures in the deployment
  if [ "$block_number_dec" -ge 1 ]; then
    echo "RPC endpoint is up"
    break
  else
    echo "RPC endpoint not yet available, retrying in $retry_interval seconds..."
    sleep $retry_interval
    continue
  fi
done

set -e

echo "Funding CREATE2 contract account..."
$EXEC_CMD "cast send --rpc-url http://\${STACK_SVC_FXETH_GETH_1}:8545 --private-key 0x888814df89c4358d7ddb3fa4b0213e7331239a80e1f013eaa7b2deca2a41a218 --value 1ether 0x3fab184622dc19b6109349b94811493bf2a45362"

echo "Deploying CREATE2 contract..."
$EXEC_CMD "cast publish --rpc-url http://\${STACK_SVC_FXETH_GETH_1}:8545 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"

echo "Deploying nitro contracts..."
$EXEC_CMD "cd /opt/nitro-contracts-runbook && txtx run deploy-nitro-contracts -u -f --input secret_key=0x\${BPI_NITRO_CHAIN_PK} --input chain_id=\${BPI_CHAIN_ID:-1212} --input rpc_url=http://\${STACK_SVC_FXETH_GETH_1}:8545"

echo "Success, go-nitro contracts deployed"
touch "${BPI_SO_DEPLOYMENT_DIR}/.init_complete"
