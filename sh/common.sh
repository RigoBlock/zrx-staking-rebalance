#!/usr/bin/env bash
set -euo pipefail

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Remember any user-provided values so they take precedence over .env.
USER_RPC_URL="${RPC_URL:-}"
USER_SAFE_TX_SERVICE_URL="${SAFE_TX_SERVICE_URL:-}"
USER_CHAIN_ID="${CHAIN_ID:-}"

if [ -f "$REPO_ROOT/.env" ]; then
  # shellcheck source=/dev/null
  set -a && source "$REPO_ROOT/.env" && set +a
fi

[ -n "$USER_RPC_URL" ] && export RPC_URL="$USER_RPC_URL"
[ -n "$USER_SAFE_TX_SERVICE_URL" ] && export SAFE_TX_SERVICE_URL="$USER_SAFE_TX_SERVICE_URL"
[ -n "$USER_CHAIN_ID" ] && export CHAIN_ID="$USER_CHAIN_ID"

: "${RPC_URL:?RPC_URL must be set as an environment variable or in .env}"

DEFAULT_POOLS="[0x0000000000000000000000000000000000000000000000000000000000000031,0x0000000000000000000000000000000000000000000000000000000000000048,0x0000000000000000000000000000000000000000000000000000000000000034]"

# Convert a human-readable amount (e.g. 1.5) to wei.
to_wei() {
  cast --to-wei "$1" ether
}

# Build a bytes32 array literal from positional arguments.
build_pool_array() {
  if [ "$#" -eq 0 ]; then
    echo "$DEFAULT_POOLS"
    return
  fi
  local arr="["
  local first=1
  for p in "$@"; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      arr="$arr,"
    fi
    # Normalize to 66 characters (0x + 64 hex).
    local clean="${p#0x}"
    clean="$(printf '%064s' "$clean" | tr ' ' '0')"
    arr="$arr 0x$clean"
  done
  arr="$arr ]"
  echo "$arr"
}
