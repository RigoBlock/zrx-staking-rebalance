#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SCRIPT="$1"
CONTRACT_NAME="$(basename "$SCRIPT" .s.sol)"
shift

BROADCAST_FLAG="--broadcast"
if [ -n "${DRY_RUN:-}" ] || [ -n "${WRITE_PLAN:-}" ]; then
  BROADCAST_FLAG=""
fi

SIGNER_FLAGS=()
if [ -n "${PRIVATE_KEY:-}" ]; then
  SIGNER_FLAGS+=(--private-key "$PRIVATE_KEY")
fi
if [ -n "${LEDGER:-}" ]; then
  SIGNER_FLAGS+=(--ledger)
fi
if [ -n "${TREZOR:-}" ]; then
  SIGNER_FLAGS+=(--trezor)
fi
if [ -n "${MNEMONIC_INDEX:-}" ]; then
  SIGNER_FLAGS+=(--mnemonic-index "$MNEMONIC_INDEX")
fi
if [ -n "${HD_PATHS:-}" ]; then
  SIGNER_FLAGS+=(--hd-paths "$HD_PATHS")
fi

mkdir -p "$REPO_ROOT/out"

if [ -n "${WRITE_PLAN:-}" ]; then
  LOG_FILE="$(mktemp)"
  # shellcheck disable=SC2086
  forge script "${SCRIPT}:${CONTRACT_NAME}" \
    --rpc-url "$RPC_URL" \
    --slow \
    "${SIGNER_FLAGS[@]}" \
    "$@" 2>&1 | tee "$LOG_FILE"

  awk '/---PLAN_JSON_START---/{flag=1;next}/---PLAN_JSON_END---/{flag=0}flag' "$LOG_FILE" \
    > "$REPO_ROOT/out/plan.json"
  rm -f "$LOG_FILE"

  if [ ! -s "$REPO_ROOT/out/plan.json" ]; then
    echo "ERROR: could not extract plan JSON from script output" >&2
    exit 1
  fi
  echo "Plan written to $REPO_ROOT/out/plan.json"
else
  # shellcheck disable=SC2086
  forge script "${SCRIPT}:${CONTRACT_NAME}" \
    --rpc-url "$RPC_URL" \
    $BROADCAST_FLAG \
    --slow \
    "${SIGNER_FLAGS[@]}" \
    "$@"
fi
