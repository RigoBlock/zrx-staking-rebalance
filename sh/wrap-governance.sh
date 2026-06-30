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
  unstake)
    MODE_UINT=0
    ;;
  full)
    MODE_UINT=1
    ;;
  liquid)
    MODE_UINT=2
    ;;
  exclude-pools)
    MODE_UINT=3
    ;;
  *)
    echo "unknown wrap mode: $MODE" >&2
    exit 1
    ;;
esac

STAKER="${STAKER:-0x0000000000000000000000000000000000000000}"
DELEGATEE="${DELEGATEE:-0x0000000000000000000000000000000000000000}"
POOLS_CSV="${POOLS:-}"
if [ "$#" -gt 0 ]; then
  POOLS_CSV="$1"
  shift
fi

echo "=============================================="
echo "WrapGovernance operation"
echo "  mode:        $MODE"
echo "  mode uint:   $MODE_UINT"
echo "  staker:      $STAKER"
echo "  delegatee:   $DELEGATEE"
echo "  pools csv:   ${POOLS_CSV:-<default>}"
echo "  broadcast:   $BROADCAST"
echo "=============================================="

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

"$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/WrapGovernance.s.sol" \
  --sig "run(uint8,address,address,string)" \
  "$MODE_UINT" "$STAKER" "$DELEGATEE" "$POOLS_CSV"

RUN_DIR="dry-run"
[ "$BROADCAST" = true ] && RUN_DIR=""
BROADCAST_FILE="$REPO_ROOT/broadcast/WrapGovernance.s.sol/1/${RUN_DIR:+${RUN_DIR}/}run-latest.json"

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
