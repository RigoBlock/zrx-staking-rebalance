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

# Default: stake and delegate the full available balance.
AMOUNT="$MAX_UINT"
if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  AMOUNT="$(to_wei "$1")"
  shift
elif [ -n "${AMOUNT:-}" ]; then
  AMOUNT="$(to_wei "$AMOUNT")"
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/StakeAndDelegate.s.sol" \
  --sig "run(uint256,uint256)" \
  "$AMOUNT" "$AMOUNT"
