#!/usr/bin/env bash
# Safe Transaction Service helpers. Modeled after 0x Settler's common_safe.sh.
# We compute the Safe transaction hash via the Safe contract (cast call), sign
# with cast wallet sign, and POST to the Safe Transaction Service.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# SAFE_TX_SERVICE_URL is defined in sh/constants.sh (mainnet only).

# Zeroed Safe gas/refund parameters. The Safe Transaction Service requires them
# in the payload even though they are unused for a standard off-chain proposal.
readonly SAFE_ZERO_ADDR="0x0000000000000000000000000000000000000000"

function safe_api_url {
  echo "$SAFE_TX_SERVICE_URL"
}

# Compute the Safe transaction hash by calling the Safe contract.
# Args: safe to value data operation nonce
function safe_tx_hash {
  local safe="$1"
  local to="$2"
  local value="$3"
  local data="$4"
  local operation="$5"
  local nonce="$6"

  cast call --rpc-url "$RPC_URL" "$safe" \
    "getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)" \
    "$to" "$value" "$data" "$operation" 0 0 0 "$SAFE_ZERO_ADDR" "$SAFE_ZERO_ADDR" "$nonce"
}

# Propose a transaction to the Safe Transaction Service.
# Args: safe to value data operation nonce sender signature
function safe_propose {
  local safe="$1"
  local to="$2"
  local value="$3"
  local data="$4"
  local operation="$5"
  local nonce="$6"
  local sender="$7"
  local signature="$8"

  local safe_tx_hash
  safe_tx_hash="$(safe_tx_hash "$safe" "$to" "$value" "$data" "$operation" "$nonce")"

  local payload
  payload="$(jq -n \
    --arg to "$to" \
    --arg value "$value" \
    --arg data "$data" \
    --arg operation "$operation" \
    --arg safeTxGas "0" \
    --arg baseGas "0" \
    --arg gasPrice "0" \
    --arg gasToken "$SAFE_ZERO_ADDR" \
    --arg refundReceiver "$SAFE_ZERO_ADDR" \
    --arg nonce "$nonce" \
    --arg contractTransactionHash "$safe_tx_hash" \
    --arg sender "$sender" \
    --arg signature "$signature" \
    --arg origin "${SAFE_ORIGIN:-zrx-staking-rebalance}" \
    '{
      to: $to,
      value: $value,
      data: $data,
      operation: ($operation | tonumber),
      safeTxGas: $safeTxGas,
      baseGas: $baseGas,
      gasPrice: $gasPrice,
      gasToken: $gasToken,
      refundReceiver: $refundReceiver,
      nonce: ($nonce | tonumber),
      contractTransactionHash: $contractTransactionHash,
      sender: $sender,
      signature: $signature,
      origin: $origin
    }')"

  curl -s -X POST "$(safe_api_url)/v1/safes/$safe/multisig-transactions/" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

# Confirm an existing Safe transaction by posting an owner signature.
# Args: safeTxHash signature
function safe_confirm {
  local safe_tx_hash="$1"
  local signature="$2"

  local payload
  payload="$(jq -n --arg signature "$signature" '{signature: $signature}')"

  curl -s -X POST "$(safe_api_url)/v1/multisig-transactions/$safe_tx_hash/confirmations/" \
    -H "Content-Type: application/json" \
    -d "$payload"
}
