#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORGE_STD_DIR="$REPO_ROOT/lib/forge-std"

if [ ! -d "$FORGE_STD_DIR/.git" ]; then
  echo "Installing forge-std..."
  mkdir -p "$REPO_ROOT/lib"
  git clone --depth 1 --branch v1.9.4 https://github.com/foundry-rs/forge-std.git "$FORGE_STD_DIR"
else
  echo "forge-std already installed."
fi

echo "Foundry dependencies ready."
