#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

PLAN="${1:?plan.json required}"
SAFE="${2:?Safe address required}"
shift 2

PRIVATE_KEY=""
SENDER=""
LEDGER=""
TREZOR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --private-key)
      PRIVATE_KEY="$2"
      shift 2
      ;;
    --sender)
      SENDER="$2"
      shift 2
      ;;
    --ledger)
      LEDGER="1"
      shift
      ;;
    --trezor)
      TREZOR="1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$SENDER" ] && [ -n "$PRIVATE_KEY" ]; then
  SENDER="$(cast wallet address --private-key "$PRIVATE_KEY")"
fi

if [ -z "$SENDER" ]; then
  echo "--sender <address> is required for ledger/trezor, or derive via --private-key"
  exit 1
fi

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"

# Pick Safe Transaction Service URL based on chain id if not provided.
if [ -z "${SAFE_TX_SERVICE_URL:-}" ]; then
  case "$CHAIN_ID" in
    1) SAFE_TX_SERVICE_URL="https://safe-transaction-mainnet.safe.global" ;;
    11155111) SAFE_TX_SERVICE_URL="https://safe-transaction-sepolia.safe.global" ;;
    *)
      echo "Unknown chain id $CHAIN_ID; set SAFE_TX_SERVICE_URL"
      exit 1
      ;;
  esac
fi

SIGNER_FLAGS=()
if [ -n "$PRIVATE_KEY" ]; then
  SIGNER_FLAGS+=(--private-key "$PRIVATE_KEY")
fi
if [ -n "$LEDGER" ]; then
  SIGNER_FLAGS+=(--ledger)
fi
if [ -n "$TREZOR" ]; then
  SIGNER_FLAGS+=(--trezor)
fi

STEPS="$(jq length "$PLAN")"
NONCE="$(curl -s "$SAFE_TX_SERVICE_URL/api/v1/safes/$SAFE/" | jq -r '.nonce')"

echo "Proposing $STEPS transaction(s) to Safe $SAFE (chain $CHAIN_ID, nonce $NONCE)"

for ((i = 0; i < STEPS; i++)); do
  TO="$(jq -r ".[$i].to" "$PLAN")"
  VALUE="$(jq -r ".[$i].value" "$PLAN")"
  DATA="$(jq -r ".[$i].data" "$PLAN")"
  DESCRIPTION="$(jq -r ".[$i].description // empty" "$PLAN")"

  echo ""
  echo "[$((i + 1))/$STEPS] $DESCRIPTION"
  echo "  to: $TO"
  echo "  value: $VALUE"

  SAFE_TX_JSON=$(forge script "$REPO_ROOT/script/SafeTx.s.sol:SafeTx" \
    --rpc-url "$RPC_URL" \
    --sig "run(address,address,uint256,bytes,uint8,uint256)" \
    "$SAFE" "$TO" "$VALUE" "$DATA" 0 "$NONCE" 2>&1 | \
    awk '/---SAFE_TX_JSON_START---/{flag=1;next}/---SAFE_TX_JSON_END---/{flag=0}flag')

  if [ -z "$SAFE_TX_JSON" ]; then
    echo "ERROR: could not extract Safe transaction JSON from script output" >&2
    exit 1
  fi

  SAFE_TX_HASH="$(echo "$SAFE_TX_JSON" | jq -r '.safeTxHash')"
  echo "  safeTxHash: $SAFE_TX_HASH"

  SIGNATURE="$(cast wallet sign "${SIGNER_FLAGS[@]}" --no-hash "$SAFE_TX_HASH")"

  PAYLOAD=$(jq -n \
    --arg to "$TO" \
    --arg value "$VALUE" \
    --arg data "$DATA" \
    --arg operation "0" \
    --arg safeTxGas "0" \
    --arg baseGas "0" \
    --arg gasPrice "0" \
    --arg gasToken "0x0000000000000000000000000000000000000000" \
    --arg refundReceiver "0x0000000000000000000000000000000000000000" \
    --arg nonce "$NONCE" \
    --arg contractTransactionHash "$SAFE_TX_HASH" \
    --arg sender "$SENDER" \
    --arg signature "$SIGNATURE" \
    --arg origin "zrx-staking-rebalance" \
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
    }')

  curl -s -X POST "$SAFE_TX_SERVICE_URL/api/v1/safes/$SAFE/multisig-transactions/" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" | jq .

  NONCE=$((NONCE + 1))
done

echo ""
echo "Done. Review the transactions in the Safe UI."
