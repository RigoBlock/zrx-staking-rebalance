#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

BROADCAST=false
PLAN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --broadcast)
      BROADCAST=true
      shift
      ;;
    --plan)
      PLAN=true
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

SIG="run(string,address,uint256,bytes32[])"
if [ "$PLAN" = true ]; then
  SIG="generatePlan(string,address,uint256,bytes32[])"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi
if [ "$PLAN" = true ]; then
  FLAGS+=(--plan)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/Redelegate.s.sol" \
  --sig "$SIG" \
  "$MODE" "$STAKER" "$TARGET_AMOUNT" "$POOLS"
