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

MODE="$1"
shift

case "$MODE" in
  undelegate-all)
    MODE_UINT=0
    ;;
  redelegate-all)
    MODE_UINT=1
    ;;
  redelegate-amount)
    MODE_UINT=2
    ;;
  *)
    echo "unknown redelegate mode: $MODE" >&2
    exit 1
    ;;
esac

# redelegate-amount can take an optional target amount; other modes ignore it.
# 0 means "rebalance to the current total delegated".
TARGET_AMOUNT="0"
if [ "$MODE" = "redelegate-amount" ]; then
  if [ "$#" -gt 0 ] && printf '%s\n' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    TARGET_AMOUNT="$(to_wei "$1")"
    shift
  elif [ -n "${AMOUNT:-}" ]; then
    TARGET_AMOUNT="$(to_wei "$AMOUNT")"
  fi
fi

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/Redelegate.s.sol" \
  --sig "run(uint8,uint256)" \
  "$MODE_UINT" "$TARGET_AMOUNT"
