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

# Default: delegate the entire undelegated balance.
# stakeAmount=0 means "do not stake"; delegateAmount=USE_FULL_BALANCE means "delegate all".
DELEGATE_AMOUNT="$MAX_UINT"
if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  DELEGATE_AMOUNT="$(to_wei "$1")"
  shift
elif [ -n "${AMOUNT:-}" ]; then
  DELEGATE_AMOUNT="$(to_wei "$AMOUNT")"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "run(uint256,uint256)" \
  "0" "$DELEGATE_AMOUNT"
