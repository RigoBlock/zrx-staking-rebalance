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

MODE="$1"
shift

case "$MODE" in
  undelegate-all)
    MODE_UINT=0
    ;;
  redelegate-all)
    MODE_UINT=1
    ;;
  redelegate-amount)
    MODE_UINT=2
    ;;
  *)
    echo "unknown redelegate mode: $MODE" >&2
    exit 1
    ;;
esac

# redelegate-amount can take an optional target amount; other modes ignore it.
# 0 means "rebalance to the current total delegated".
TARGET_AMOUNT="0"
if [ "$MODE" = "redelegate-amount" ]; then
  if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    TARGET_AMOUNT="$(to_wei "$1")"
    shift
  elif [ -n "${AMOUNT:-}" ]; then
    TARGET_AMOUNT="$(to_wei "$AMOUNT")"
  fi
fi

POOLS_CSV="${POOLS:-}"
if [ "$#" -gt 0 ]; then
  POOLS_CSV="$1"
  shift
fi
STAKER="${STAKER:-0x0000000000000000000000000000000000000000}"

echo "=============================================="
echo "Redelegate operation"
echo "  mode:           $MODE"
echo "  mode uint:      $MODE_UINT"
echo "  staker:         $STAKER"
echo "  target amount:  $TARGET_AMOUNT"
echo "  pools csv:      ${POOLS_CSV:-<default>}"
echo "  broadcast:      $BROADCAST"
echo "=============================================="

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

"$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/Redelegate.s.sol" \
  --sig "run(uint8,address,uint256,string)" \
  "$MODE_UINT" "$STAKER" "$TARGET_AMOUNT" "$POOLS_CSV"

# Print calldata for each transaction in the broadcast output.
RUN_DIR="dry-run"
[ "$BROADCAST" = true ] && RUN_DIR=""
BROADCAST_FILE="$REPO_ROOT/broadcast/Redelegate.s.sol/1/${RUN_DIR:+${RUN_DIR}/}run-latest.json"

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
