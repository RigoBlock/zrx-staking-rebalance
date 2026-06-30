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

# Default: delegate the entire undelegated balance.
# stakeAmount=0 means "do not stake"; delegateAmount=USE_FULL_BALANCE means "delegate all".
DELEGATE_AMOUNT="$MAX_UINT"
if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  DELEGATE_AMOUNT="$(to_wei "$1")"
  shift
fi

STAKER="${STAKER:-0x0000000000000000000000000000000000000000}"
POOLS_CSV="${POOLS:-}"
if [ "$#" -gt 0 ]; then
  POOLS_CSV="$1"
  shift
fi

echo "=============================================="
echo "DelegateEqual operation"
echo "  staker:          $STAKER"
echo "  stake amount:    0"
echo "  delegate amount: $DELEGATE_AMOUNT"
echo "  pools csv:       ${POOLS_CSV:-<default>}"
echo "  broadcast:       $BROADCAST"
echo "=============================================="

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

"$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "run(address,uint256,uint256,string)" \
  "$STAKER" "0" "$DELEGATE_AMOUNT" "$POOLS_CSV"

RUN_DIR="dry-run"
[ "$BROADCAST" = true ] && RUN_DIR=""
BROADCAST_FILE="$REPO_ROOT/broadcast/StakeAndDelegate.s.sol/1/${RUN_DIR:+${RUN_DIR}/}run-latest.json"

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
