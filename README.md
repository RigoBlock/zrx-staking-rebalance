# zrx-staking-rebalance

A utility to reallocate 0x (ZRX) staking positions across specific staking pools
and optionally migrate ZRX to the wrapped-ZRX governance token.

Operations are implemented as native Foundry scripts in `script/*.s.sol` and can
be run through the interactive runner (`yarn op`), per-action package scripts,
or the shell wrappers directly.

## Project structure

```
script/                   # Foundry Solidity scripts
  StakeAndDelegate.s.sol
  Redelegate.s.sol
  WrapGovernance.s.sol
  WrapGovernanceMultiDelegate.s.sol
  TreasuryMigration.s.sol
sh/                       # Bash wrappers and the interactive runner
  common.sh               # Shared shell helpers
  op.sh                   # Interactive runner
  run-forge.sh            # Low-level forge script wrapper
  stake-and-delegate.sh
  delegate-equal.sh
  redelegate.sh
  wrap-governance.sh
  treasury.sh
src/
  interfaces/             # Minimal Solidity contract interfaces
  constants/Constants.sol # Mainnet addresses and target pool ids
  libraries/              # Shared helpers (LibStaking, LibSafeChild)
test/
  Fixtures.sol            # Common test setup helpers
  Operations.t.sol        # Foundry fork tests (direct script execution)
  SafeExecution.t.sol     # Foundry fork tests (execute from the Safe address)
```

`WrapGovernanceMultiDelegate` wraps ZRX into wZRX and splits it across
multiple **1-of-1 child Safe wallets** (one per delegatee). Each child Safe is
deterministically deployed from the master Safe via the official Safe v1.3.0
proxy factory, owned solely by the master Safe, and delegates its wZRX to the
intended address.

## Install

Requires [Foundry](https://book.getfoundry.sh/).

```bash
# Install / update Foundry libraries
./sh/install-foundry-deps.sh

# Compile Solidity
yarn build
# or: forge build
```

## Configuration

Copy `.env.example` to `.env` and set at least `RPC_URL`:

```bash
cp .env.example .env
# edit .env
```

| Variable | Purpose |
|----------|---------|
| `RPC_URL` | Ethereum JSON-RPC endpoint (required) |

## Key addresses

All on-chain addresses live in `src/constants/Constants.sol`.

- `OLD_ZRX_TREASURY` and `NEW_ZRX_TREASURY` are the 0x governance treasury
  **contracts** (timelock/Governor style), not Safe wallets.
- `LEGACY_STAKE_SAFE_OWNER` (`0x5775afA796818ADA27b09FaF5c90d101f04eF600`) is
  the Safe multisig that owns the delegated stake in the legacy ZRX staking
  system.
- `OX_LABS_DEPLOYMENT_SAFE` (`0x8E5DE7118a596E99B0563D3022039c11927f4827`) is
  the new 0x Labs deployment Safe (taken from 0x Settler's mainnet
  `chain_config.json`).

## Run an operation

### Interactive runner (recommended)

```bash
yarn op
```

This prompts for:

1. Operation (stake-delegate, delegate-equal, redelegate, wrap, treasury)
2. Staker / proposer address
3. Operation parameters (amount, pools, mode, delegatee, etc.)
4. Signer (private key, Ledger, Trezor, or mnemonic)
5. Simulate or execute

The runner prints a summary, streams the forge output to the terminal, and
never logs the private key.

### Per-action scripts

Each operation has two package scripts:

- `op:<name>` — execute (broadcast, adds Foundry's `--broadcast` flag)
- `op:sim:<name>` — simulate (no `--broadcast`, Foundry runs locally)

Foundry scripts simulate by default and only broadcast when `--broadcast` is
passed, so `op:sim:*` is the same script without that flag.

Examples:

```bash
# Stake 1,000,000 ZRX and delegate equally across the 3 target pools
yarn op:stake-delegate 0x... 1000000

# Simulate first
yarn op:sim:stake-delegate 0x... 1000000

# Delegate 1,000,000 ZRX of existing undelegated stake equally across target pools
yarn op:delegate-equal 0x... 1000000

# Undelegate all active stake
yarn op:redelegate undelegate-all 0x...

# Undelegate all active stake and redelegate equally to target pools
yarn op:redelegate redelegate-all 0x...

# Rebalance so the target pools total exactly 2,000,000 ZRX
yarn op:redelegate redelegate-amount 0x... 2000000

# Wrap already-liquid ZRX into wZRX governance and delegate
yarn op:wrap liquid 0x... 0x... 1000000

# Full legacy-stake migration: undelegate all, advance epoch, unstake, wrap, delegate
yarn op:wrap full 0x... 0x... 1000000

# Undelegate from non-target pools, advance epoch, unstake, wrap, delegate
yarn op:wrap exclude-pools 0x... 0x... 1000000 \
  0x0000000000000000000000000000000000000000000000000000000000000031


# Propose migrating old ZRX treasury assets to the new governance treasury
yarn op:treasury propose 0x...

# Execute the proposal after it has passed
yarn op:treasury execute 0x... <proposalId>
```

Default target pools are `0x31`, `0x48`, `0x34`. Override by appending pool ids:

```bash
yarn op:redelegate redelegate-all 0x... 0x31 0x48 0x32
```

### Direct shell usage

```bash
# Broadcast (requires a signer)
PRIVATE_KEY=0x... ./sh/stake-and-delegate.sh --broadcast 0x... 1000000
LEDGER=1 ./sh/redelegate.sh --broadcast redelegate-all 0x...

# Simulate (no signer required beyond the --from address)
./sh/redelegate.sh redelegate-all 0x...
```

## Hardware wallets

Foundry supports hardware wallets natively:

```bash
LEDGER=1 yarn op:redelegate redelegate-all 0x...
TREZOR=1 yarn op:wrap liquid 0x... 0x... 1000
```

Always simulate first with `yarn op:sim:*` (no `--broadcast`).

## Tests

```bash
yarn build              # Compile Foundry scripts
yarn lint               # Run forge lint
yarn test:foundry       # Foundry fork tests (requires RPC_URL)
```

Fork tests are pinned to the mainnet block defined by `Constants.FORK_BLOCK_NUMBER`
so each run is reproducible. Foundry caches forked RPC state in
`~/.foundry/cache/rpc`; in CI this directory is cached so the pinned block is only
fetched once per PR. Tests fail explicitly when `RPC_URL` is not set.

Tests call the script `run()` functions directly and mock chain state (balances,
storage slots, time) on the fork, so the same execution code is exercised without
needing a separate plan-generation path.

## Security

See [`docs/SECURITY.md`](docs/SECURITY.md).

- Private keys are prompted (hidden) by the interactive runner or supplied via
  `PRIVATE_KEY` only for the subprocess lifetime.
- Prefer hardware wallets for production operations.
- Simulate every operation before broadcasting.

## Repository access

Only authorized maintainers may create branches or merge to `main`. See
[`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md) for the required GitHub settings.

## License

Undecided. This repository is currently private and will be made public later.
See `LICENSE` for the placeholder status.
