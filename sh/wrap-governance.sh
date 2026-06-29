#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

MODE="$1"
STAKER="$2"
DELEGATEE="$3"
AMOUNT="$4"
shift 4

WEI="$(to_wei "$AMOUNT")"
EXCLUDE_POOLS="[0x0000000000000000000000000000000000000000000000000000000000000031]"

if [ "$#" -gt 0 ]; then
  EXCLUDE_POOLS="$(build_pool_array "$@")"
fi

exec "$(dirname "$0")/run-forge.sh" "$REPO_ROOT/script/WrapGovernance.s.sol" \
  --sig "run(string,address,address,uint256,bytes32[])" \
  "$MODE" "$STAKER" "$DELEGATEE" "$WEI" "$EXCLUDE_POOLS"
