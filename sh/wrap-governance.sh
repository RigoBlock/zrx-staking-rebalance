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
  unstake)
    MODE_UINT=0
    ;;
  full)
    MODE_UINT=1
    ;;
  liquid)
    MODE_UINT=2
    ;;
  exclude-pools)
    MODE_UINT=3
    ;;
  *)
    echo "unknown wrap mode: $MODE" >&2
    exit 1
    ;;
esac

FLAGS=()
if [ "$BROADCAST" = true ]; then
  FLAGS+=(--broadcast)
fi

exec "$(dirname "$0")/run-forge.sh" "${FLAGS[@]}" "$REPO_ROOT/script/WrapGovernance.s.sol" \
  --sig "run(uint8)" \
  "$MODE_UINT"
