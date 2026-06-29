#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

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

exec "$(dirname "$0")/run-forge.sh" "$REPO_ROOT/script/TreasuryMigration.s.sol" \
  --sig "run(string,address,bytes32[],uint256)" \
  "$MODE" "$PROPOSER" "$OPERATED_POOLS" "$PROPOSAL_ID"
