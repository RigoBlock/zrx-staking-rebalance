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

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

if [ "$MODE" = "execute" ]; then
  PROPOSAL_ID="${1:-${PROPOSAL_ID:-0}}"
  exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
    --sig "run(uint8,uint256)" \
    "$MODE_UINT" "$PROPOSAL_ID"
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
  --sig "run(uint8)" \
  "$MODE_UINT"
