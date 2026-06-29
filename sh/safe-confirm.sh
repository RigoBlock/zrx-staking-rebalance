#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common_safe.sh"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [<safe-address>] <safe-tx-hash> [--private-key <key> | --ledger | --trezor | --signature <sig> --sender <addr>]"
  echo "Default Safe address: $SAFE_ADDRESS"
  exit 1
fi

# First positional arg is either the Safe address or the transaction hash.
if [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  SAFE="$1"
  shift
else
  SAFE="$SAFE_ADDRESS"
fi

SAFE_TX_HASH="$1"
shift

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

echo "Confirming Safe transaction $SAFE_TX_HASH from $SENDER"

if [ -n "$SIGNATURE" ]; then
  SIG="$SIGNATURE"
else
  SIGNER_FLAGS=()
  [ -n "$PRIVATE_KEY" ] && SIGNER_FLAGS+=(--private-key "$PRIVATE_KEY")
  [ -n "$LEDGER" ] && SIGNER_FLAGS+=(--ledger --from "$SENDER")
  [ -n "$TREZOR" ] && SIGNER_FLAGS+=(--trezor --from "$SENDER")
  SIG="$(cast wallet sign "${SIGNER_FLAGS[@]}" --no-hash "$SAFE_TX_HASH")"
fi

safe_confirm "$SAFE_TX_HASH" "$SIG" | jq .
