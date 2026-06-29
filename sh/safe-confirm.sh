#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SAFE="${1:?Safe address required}"
SAFE_TX_HASH="${2:?safeTxHash required}"
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

echo "Confirming Safe transaction $SAFE_TX_HASH from $SENDER"

SIGNATURE="$(cast wallet sign "${SIGNER_FLAGS[@]}" --no-hash "$SAFE_TX_HASH")"

PAYLOAD="$(jq -n --arg signature "$SIGNATURE" '{signature: $signature}')"

curl -s -X POST "$SAFE_TX_SERVICE_URL/api/v1/multisig-transactions/$SAFE_TX_HASH/confirmations/" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | jq .
