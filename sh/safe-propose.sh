#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common_safe.sh"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <safe-address> [plan.json] [--private-key <key> | --ledger | --trezor | --signature <sig> --sender <addr>]"
  exit 1
fi

SAFE="$1"
shift

if [ "$#" -ge 1 ] && [ -f "$1" ]; then
  PLAN="$1"
  shift
else
  PLAN="$REPO_ROOT/out/plan.json"
fi

PRIVATE_KEY=""
SENDER=""
LEDGER=""
TREZOR=""
SIGNATURE=""

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
    --signature)
      SIGNATURE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$SENDER" ] && [ -n "$PRIVATE_KEY" ]; then
  SENDER="$(cast wallet address --private-key "$PRIVATE_KEY")"
fi

if [ -z "$SENDER" ]; then
  echo "--sender <address> is required for ledger/trezor, or derive via --private-key" >&2
  exit 1
fi

STEPS="$(jq length "$PLAN")"
NONCE="$(cast call --rpc-url "$RPC_URL" "$SAFE" 'nonce()(uint256)')"

echo "Proposing $STEPS transaction(s) to Safe $SAFE (nonce $NONCE)"

for ((i = 0; i < STEPS; i++)); do
  TO="$(jq -r ".[$i].to" "$PLAN")"
  VALUE="$(jq -r ".[$i].value" "$PLAN")"
  DATA="$(jq -r ".[$i].data" "$PLAN")"
  DESCRIPTION="$(jq -r ".[$i].description // empty" "$PLAN")"

  echo ""
  echo "[$((i + 1))/$STEPS] $DESCRIPTION"

  SAFE_TX_HASH="$(safe_tx_hash "$SAFE" "$TO" "$VALUE" "$DATA" 0 "$NONCE")"
  echo "  safeTxHash: $SAFE_TX_HASH"

  if [ -n "$SIGNATURE" ]; then
    SIG="$SIGNATURE"
  else
    SIGNER_FLAGS=()
    [ -n "$PRIVATE_KEY" ] && SIGNER_FLAGS+=(--private-key "$PRIVATE_KEY")
    [ -n "$LEDGER" ] && SIGNER_FLAGS+=(--ledger --from "$SENDER")
    [ -n "$TREZOR" ] && SIGNER_FLAGS+=(--trezor --from "$SENDER")
    SIG="$(cast wallet sign "${SIGNER_FLAGS[@]}" --no-hash "$SAFE_TX_HASH")"
  fi

  safe_propose "$SAFE" "$TO" "$VALUE" "$DATA" 0 "$NONCE" "$SENDER" "$SIG" | jq .

  NONCE=$((NONCE + 1))
done

echo ""
echo "Done. Review the transactions in the Safe UI."
