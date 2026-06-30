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

STAKER="$1"
AMOUNT="$2"
shift 2

POOLS="$(build_pool_array "$@")"
WEI="$(to_wei "$AMOUNT")"

SIG="run(address,uint256,uint256,bytes32[])"
if [ "$PLAN" = true ]; then
  SIG="generatePlan(address,uint256,uint256,bytes32[])"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi
if [ "$PLAN" = true ]; then
  FLAGS+=(--plan)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "$SIG" \
  "$STAKER" "0" "$WEI" "$POOLS"
