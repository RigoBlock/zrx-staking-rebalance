# zrx-staking-rebalance

A utility to reallocate 0x (ZRX) staking positions across specific staking pools
and optionally migrate ZRX to the wrapped-ZRX governance token.

Operations are implemented as native Foundry scripts in `script/*.s.sol` and can
be run through the interactive runner (`yarn op`), per-action package scripts,
or the shell wrappers directly.

## Project structure

```
script/                   # Foundry Solidity scripts
  Constants.sol           # Mainnet addresses and target pool ids
  LibStaking.sol          # Pure staking calldata helpers
  LibScript.sol           # Shared script utilities (env, plan JSON)
  StakeAndDelegate.s.sol
  Redelegate.s.sol
  WrapGovernance.s.sol
  TreasuryMigration.s.sol
sh/                       # Bash wrappers, Safe helpers, constants, and the interactive runner
  common_safe.sh          # Safe hash/sign/post helpers
  constants.sh            # Safe-related constants
  safe-propose.sh         # Propose a plan to a Safe
  safe-confirm.sh         # Confirm a Safe transaction
src/interfaces/           # Minimal Solidity contract interfaces
test/
  Operations.t.sol        # Foundry fork tests (direct script execution)
  SafeExecution.t.sol     # Foundry fork tests (execute proposed Safe calldata)
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

All on-chain addresses live in `script/Constants.sol`.

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

Most operations have three package scripts:

- `op:<name>` — execute (broadcast)
- `op:sim:<name>` — simulate (`DRY_RUN=1`)
- `op:plan:<name>` — write a JSON plan to `out/plan.json` (`WRITE_PLAN=1`)

Plan mode is available for the staking/redelegation operations. Wrap and
treasury operations support simulate and execute, but not plan output, because
they include time-dependent or governance-specific steps.

Examples:

```bash
# Stake 1,000,000 ZRX and delegate equally across the 3 target pools
yarn op:stake-delegate 0x... 1000000

# Simulate first
yarn op:sim:stake-delegate 0x... 1000000

# Write a plan JSON instead of broadcasting
yarn op:plan:stake-delegate 0x... 1000000

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
PRIVATE_KEY=0x... ./sh/stake-and-delegate.sh 0x... 1000000
LEDGER=1 ./sh/redelegate.sh redelegate-all 0x...
WRITE_PLAN=1 ./sh/wrap-governance.sh liquid 0x... 0x... 1000
```

### Plans and Safe transactions

Generate a JSON plan without broadcasting:

```bash
WRITE_PLAN=1 yarn op:stake-delegate 0x... 1000000
cat out/plan.json
```

Propose the plan to a Safe:

```bash
# Propose to the default 0x Labs deployment Safe
./sh/safe-propose.sh out/plan.json --private-key 0x...
# or with a hardware wallet
./sh/safe-propose.sh out/plan.json --ledger --sender 0x<ownerAddress>
# or pass an offline signature
SIG=$(cast wallet sign --no-hash 0x<safeTxHash>)
./sh/safe-propose.sh out/plan.json --signature $SIG --sender 0x<ownerAddress>

# Target a different Safe by passing its address
./sh/safe-propose.sh 0x<safeAddress> out/plan.json --private-key 0x...
```

`sh/safe-propose.sh` computes the Safe transaction hash through the Safe
contract, signs it with `cast wallet sign`, and POSTs it to the Safe Transaction
Service. Each plan step becomes a separate Safe transaction. The service URL is a
constant in `sh/constants.sh` (mainnet only).

Additional owners can confirm the proposal from the command line:

```bash
# Confirm for the default Safe
./sh/safe-confirm.sh 0x<safeTxHash> --private-key 0x...
# or with a hardware wallet
SIG=$(cast wallet sign --no-hash 0x<safeTxHash>)
./sh/safe-confirm.sh 0x<safeTxHash> --signature $SIG --sender 0x<ownerAddress>

# Confirm for a custom Safe
./sh/safe-confirm.sh 0x<safeAddress> 0x<safeTxHash> --private-key 0x...
```

Once the threshold is reached, execute the transaction in the Safe UI.

### Default Safe wallet

Proposals are submitted to the 0x Labs deployment Safe by default:

```
0x8E5DE7118a596E99B0563D3022039c11927f4827
```

This address is taken from 0x Settler's mainnet `chain_config.json` and is the
`OX_LABS_DEPLOYMENT_SAFE` constant in `script/Constants.sol`. To target a
different Safe, set the `SAFE_ADDRESS` environment variable or pass the address
as the first argument to `safe-propose.sh` / `safe-confirm.sh`:

```bash
# Use the default Safe
./sh/safe-propose.sh out/plan.json --private-key 0x...

# Use a custom Safe
SAFE_ADDRESS=0x... ./sh/safe-propose.sh out/plan.json --private-key 0x...
./sh/safe-propose.sh 0x... out/plan.json --private-key 0x...
```

The default is defined in `sh/constants.sh`.

## Hardware wallets

Foundry supports hardware wallets natively:

```bash
LEDGER=1 yarn op:redelegate redelegate-all 0x...
TREZOR=1 yarn op:wrap liquid 0x... 0x... 1000
```

Always simulate first with `yarn op:sim:*` or `DRY_RUN=1`.

## Tests

```bash
yarn build              # Compile Foundry scripts
yarn lint               # Run forge lint
yarn test:forge         # Foundry fork tests (requires RPC_URL)
yarn test:foundry       # alias for test:forge
```

Fork tests are pinned to the mainnet block defined by `Constants.FORK_BLOCK_NUMBER`
so each run is reproducible. Foundry caches forked RPC state in
`~/.foundry/cache/rpc`; in CI this directory is cached so the pinned block is only
fetched once per PR. Tests fail explicitly when `RPC_URL` is not set.

## Security

See [`docs/SECURITY.md`](docs/SECURITY.md).

- Private keys are prompted (hidden) by the interactive runner or supplied via
  `PRIVATE_KEY` only for the subprocess lifetime.
- Prefer hardware wallets for production operations.
- Simulate every operation before broadcasting.
- Safe transactions are proposed/confirmed with `cast` + direct Safe
  Transaction Service `curl` calls (no Safe SDK) and executed through the Safe
  UI once the threshold is reached.

## Repository access

Only authorized maintainers may create branches or merge to `main`. See
[`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md) for the required GitHub settings.

## License

Undecided. This repository is currently private and will be made public later.
See `LICENSE` for the placeholder status.
