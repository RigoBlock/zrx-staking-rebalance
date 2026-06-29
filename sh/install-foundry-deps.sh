#!/usr/bin/env bash
set -euo pipefail

# Resolve the repository root robustly even when the script is invoked via a relative path.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"

cd "$REPO_ROOT"
git submodule update --init --recursive

echo "Foundry dependencies ready."
