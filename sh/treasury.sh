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
  propose)
    MODE_UINT=0
    ;;
  execute)
    MODE_UINT=1
    ;;
  *)
    echo "unknown treasury mode: $MODE" >&2
    exit 1
    ;;
esac

PROPOSER="${PROPOSER:-${STAKER:-0x0000000000000000000000000000000000000000}}"
POOLS_CSV="${POOLS:-}"

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

if [ "$MODE" = "execute" ]; then
  PROPOSAL_ID="${1:-${PROPOSAL_ID:-0}}"
  [ "$#" -gt 0 ] && shift
  POOLS_CSV="${POOLS:-}"
  if [ "$#" -gt 0 ]; then
    POOLS_CSV="$1"
    shift
  fi

  echo "=============================================="
  echo "TreasuryMigration operation"
  echo "  mode:        $MODE"
  echo "  mode uint:   $MODE_UINT"
  echo "  proposer:    $PROPOSER"
  echo "  proposal id: $PROPOSAL_ID"
  echo "  pools csv:   ${POOLS_CSV:-<default>}"
  echo "  broadcast:   $BROADCAST"
  echo "=============================================="

  "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
    --sig "run(uint8,address,string,uint256)" \
    "$MODE_UINT" "$PROPOSER" "$POOLS_CSV" "$PROPOSAL_ID"
else
  POOLS_CSV="${POOLS:-}"
  if [ "$#" -gt 0 ]; then
    POOLS_CSV="$1"
    shift
  fi

  echo "=============================================="
  echo "TreasuryMigration operation"
  echo "  mode:        $MODE"
  echo "  mode uint:   $MODE_UINT"
  echo "  proposer:    $PROPOSER"
  echo "  pools csv:   ${POOLS_CSV:-<default>}"
  echo "  broadcast:   $BROADCAST"
  echo "=============================================="

  "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
    --sig "run(uint8,address,string,uint256)" \
    "$MODE_UINT" "$PROPOSER" "$POOLS_CSV" "0"
fi

RUN_DIR="dry-run"
[ "$BROADCAST" = true ] && RUN_DIR=""
BROADCAST_FILE="$REPO_ROOT/broadcast/TreasuryMigration.s.sol/1/${RUN_DIR:+${RUN_DIR}/}run-latest.json"

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
