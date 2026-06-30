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

STAKER="$1"
AMOUNT="$2"
shift 2

POOLS="$(build_pool_array "$@")"
WEI="$(to_wei "$AMOUNT")"

# Default: stake the amount and delegate the same amount.
STAKE_AMOUNT="$WEI"
DELEGATE_AMOUNT="$WEI"

# If no pools are supplied, behave like stake-new (do not delegate).
if [ "$#" -eq 0 ]; then
  DELEGATE_AMOUNT="0"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "run(address,uint256,uint256,bytes32[])" \
  "$STAKER" "$STAKE_AMOUNT" "$DELEGATE_AMOUNT" "$POOLS"
