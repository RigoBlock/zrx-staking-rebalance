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
PROPOSER="$2"
shift 2

PROPOSAL_ID="0"
OPERATED_POOLS="[]"

if [ "$MODE" = "execute" ]; then
  PROPOSAL_ID="$1"
  shift
fi

if [ "$#" -gt 0 ]; then
  OPERATED_POOLS="$(build_pool_array "$@")"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
  --sig "run(string,address,bytes32[],uint256)" \
  "$MODE" "$PROPOSER" "$OPERATED_POOLS" "$PROPOSAL_ID"
