#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

BROADCAST=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --broadcast)
      BROADCAST=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

STAKER="${STAKER:-0x0000000000000000000000000000000000000000}"

if [ -z "${DELEGATEES:-}" ] || [ -z "${AMOUNTS:-}" ]; then
  echo "DELEGATEES and AMOUNTS must be set as comma-separated lists" >&2
  echo "Example: DELEGATEES=0x...,0x... AMOUNTS=100,200 $0" >&2
  exit 1
fi

# Build Solidity array literals from comma-separated env vars.
IFS=',' read -ra DELEGATEE_PARTS <<< "$DELEGATEES"
IFS=',' read -ra AMOUNT_PARTS <<< "$AMOUNTS"

if [ "${#DELEGATEE_PARTS[@]}" -ne "${#AMOUNT_PARTS[@]}" ]; then
  echo "DELEGATEES and AMOUNTS must have the same length" >&2
  exit 1
fi

DELEGATEES_ARRAY="[$(printf '%s,' "${DELEGATEE_PARTS[@]}" | sed 's/,$//')]"

AMOUNTS_WEI=()
for amount in "${AMOUNT_PARTS[@]}"; do
  AMOUNTS_WEI+=("$(to_wei "$amount")")
done
AMOUNTS_ARRAY="[$(printf '%s,' "${AMOUNTS_WEI[@]}" | sed 's/,$//')]"

echo "=============================================="
echo "WrapGovernanceMultiDelegate operation"
echo "  staker:      $STAKER"
echo "  delegatees:  $DELEGATEES_ARRAY"
echo "  amounts:     $AMOUNTS_ARRAY"
echo "  broadcast:   $BROADCAST"
echo "=============================================="

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

"$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/WrapGovernanceMultiDelegate.s.sol" \
  --sig "run(address,address[],uint256[])" \
  "$STAKER" "$DELEGATEES_ARRAY" "$AMOUNTS_ARRAY"

RUN_DIR="dry-run"
[ "$BROADCAST" = true ] && RUN_DIR=""
BROADCAST_FILE="$REPO_ROOT/broadcast/WrapGovernanceMultiDelegate.s.sol/1/${RUN_DIR:+${RUN_DIR}/}run-latest.json"

if [ -f "$BROADCAST_FILE" ] && command -v jq >/dev/null 2>&1; then
  echo ""
  echo "Transactions (for Tenderly/simulator verification):"
  echo "  broadcast file: $BROADCAST_FILE"
  tx_count=$(jq '.transactions | length' "$BROADCAST_FILE")
  for i in $(seq 0 $((tx_count - 1))); do
    to=$(jq -r ".transactions[$i].transaction.to" "$BROADCAST_FILE")
    value=$(jq -r ".transactions[$i].transaction.value" "$BROADCAST_FILE")
    data=$(jq -r ".transactions[$i].transaction.input" "$BROADCAST_FILE")
    echo "  [$i] to: $to"
    echo "       value: $value"
    echo "       data:  $data"
  done
  echo "=============================================="
fi
