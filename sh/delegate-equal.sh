#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

STAKER="$1"
AMOUNT="$2"
shift 2

POOLS="$(build_pool_array "$@")"
WEI="$(to_wei "$AMOUNT")"

exec "$(dirname "$0")/run-forge.sh" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "run(address,uint256,uint256,bytes32[])" \
  "$STAKER" "0" "$WEI" "$POOLS"
