#!/usr/bin/env bash
set -euo pipefail

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Remember any user-provided RPC_URL so it takes precedence over .env.
USER_RPC_URL="${RPC_URL:-}"

if [ -f "$REPO_ROOT/.env" ]; then
  # shellcheck source=/dev/null
  set -a && source "$REPO_ROOT/.env" && set +a
fi

[ -n "$USER_RPC_URL" ] && export RPC_URL="$USER_RPC_URL"

: "${RPC_URL:?RPC_URL must be set as an environment variable or in .env}"

# Sentinel value passed to StakeAndDelegate to mean "use the full available balance/amount".
# The canonical value is Constants.USE_FULL_BALANCE in src/constants/Constants.sol.
MAX_UINT=115792089237316195423570985008687907853269984665640564039457584007913129639935

# Convert a human-readable amount (e.g. 1.5) to wei.
to_wei() {
  cast --to-wei "$1" ether
}
