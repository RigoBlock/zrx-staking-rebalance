#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

MODE="$1"
STAKER="$2"
shift 2

TARGET_AMOUNT="0"
POOLS="$DEFAULT_POOLS"

# If a numeric 3rd arg is given, treat it as the target amount.
if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  TARGET_AMOUNT="$(to_wei "$1")"
  shift
fi

# Remaining args are pools.
if [ "$#" -gt 0 ]; then
  POOLS="$(build_pool_array "$@")"
fi

exec "$(dirname "$0")/run-forge.sh" "$REPO_ROOT/script/Redelegate.s.sol" \
  --sig "run(string,address,uint256,bytes32[])" \
  "$MODE" "$STAKER" "$TARGET_AMOUNT" "$POOLS"
