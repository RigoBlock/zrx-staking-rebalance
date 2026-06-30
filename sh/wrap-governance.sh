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
DELEGATEE="$3"
AMOUNT="$4"
shift 4

WEI="$(to_wei "$AMOUNT")"
EXCLUDE_POOLS="[0x0000000000000000000000000000000000000000000000000000000000000031]"

if [ "$#" -gt 0 ]; then
  EXCLUDE_POOLS="$(build_pool_array "$@")"
fi

SIG="run(string,address,address,uint256,bytes32[])"
if [ "$PLAN" = true ]; then
  SIG="generatePlan(string,address,address,uint256,bytes32[])"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi
if [ "$PLAN" = true ]; then
  FLAGS+=(--plan)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/WrapGovernance.s.sol" \
  --sig "$SIG" \
  "$MODE" "$STAKER" "$DELEGATEE" "$WEI" "$EXCLUDE_POOLS"
