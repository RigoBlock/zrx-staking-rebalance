# Agent Guidelines

## Source control

- **Do not run any git mutation commands from this environment.** This includes `git commit`, `git push`, `git merge`, `git rebase`, `git reset --hard`, `git cherry-pick`, or anything else that changes repository history or remote refs.
- The remote is configured over HTTPS and no credentials are stored here; pushes would fail anyway.
- Prepare file edits in the working tree only. Let the user review, commit, and push changes from their own environment.

## Project commands

This is a pure Foundry project targeting Ethereum mainnet.

```bash
# Build contracts
forge build

# Run linter
forge lint

# Run tests against a mainnet fork (requires RPC_URL)
RPC_URL=<mainnet-rpc-url> forge test

# Update git submodules
./sh/install-foundry-deps.sh
```

## Key implementation notes

- `forge-std` is tracked as a git submodule at `lib/forge-std`.
- Fork tests pin a mainnet block via `Constants.FORK_BLOCK_NUMBER` and reuse cached RPC state in CI.
- Safe execution uses the `approveHash` + `execTransaction` approved-hash flow because the child Safe owner is the master Safe contract.
