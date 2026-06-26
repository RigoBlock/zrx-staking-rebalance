# zrx-staking-rebalance

A terminal utility to reallocate ZRX staking positions across specific staking
pools and optionally migrate ZRX to the new wrapped-ZRX governance token.

> **Status**: implementation complete. The Rigoblock TupleFixer address and the
> 0x ERC20 Asset Proxy address are now configured for mainnet. Hardware-wallet
> code uses real SDKs but should be validated with physical devices before
> mainnet use. See [`docs/MOCKS.md`](docs/MOCKS.md) for any remaining caveats.

## Project structure

```
src/
  cli.ts              # CLI entry point and command wiring
  cli/
    helpers.ts        # Wallet resolution, simulation, EOA sending, Safe backup
    menu.ts           # Interactive menu mode
  config/
    constants.ts      # Mainnet contract addresses and ABIs
    pools.ts          # Target pool id ↔ operator mapping
  contracts/
    staking.ts        # Staking proxy calldata encoders
    tupleFixer.ts     # Rigoblock TupleFixer integration
    zrx.ts            # ZRX ERC20 approval helpers
    wzrx.ts           # Wrapped ZRX governance helpers
  ethereum/
    client.ts         # Viem public/wallet client factory
    signer.ts         # Secure private-key prompt and wipe
    hardware.ts       # Ledger / Trezor account wrappers
  operations/
    undelegateAll.ts
    stakeNew.ts
    delegateEqual.ts
    undelegateAndDelegate.ts
    stakeAndDelegate.ts
    unstake.ts
    wrapGovernance.ts
  safe/
    kit.ts            # Safe SDK initialization + version warning
    transaction.ts    # Propose / confirm / execute Safe transactions
    decoder.ts        # Human-readable calldata decoder
tests/
  unit/               # Pure-function and encoding tests
  integration/        # Mainnet fork tests (run with RPC_URL)
```

## Install

Requires Node.js ≥ 20 and [Yarn](https://yarnpkg.com).

```bash
# Install dependencies
yarn install

# Run the CLI through tsx (no build step required)
yarn cli --help
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
| `SAFE_TX_SERVICE_URL` | Optional override for Safe Transaction Service |
| `CHAIN_ID` | Optional override (defaults to 1) |


## Usage

### Help

```bash
yarn cli help
```

### Interactive menu

```bash
yarn cli menu
```

### EOA operations

```bash
# Undelegate all stake (dry-run first)
yarn cli undelegate-all 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B --dry-run

# Stake 1,000,000 ZRX
yarn cli stake-new 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 1000000

# Delegate 3,000,000 ZRX equally across the 3 target pools
yarn cli delegate-equal 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000

# Atomic undelegate + redelegate
yarn cli redelegate 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000

# Atomic stake + delegate
yarn cli stake-and-delegate 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000

# Unstake undelegated ZRX (must wait an epoch after undelegating)
yarn cli unstake 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 1000000

# Wrap liquid ZRX into wZRX governance (does not touch delegated stake)
yarn cli wrap-governance 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000 --delegatee 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B
```

Add a 4th pool by appending its bytes32 id:

```bash
yarn cli delegate-equal 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 4000000 0x0000000000000000000000000000000000000000000000000000000000000099
```

### Safe operations

The CLI detects Safe wallets by contract bytecode or the hardcoded Safe address.
Use `--force-safe` to force Safe mode.

```bash
# Create/propose an undelegate-all Safe transaction
yarn cli undelegate-all 0x5775afA796818ADA27b09FaF5c90d101f04eF600

# List pending Safe transactions
yarn cli safe pending 0x5775afA796818ADA27b09FaF5c90d101f04eF600

# Show a single Safe transaction and its signatures
yarn cli safe show 0x5775afA796818ADA27b09FaF5c90d101f04eF600 <safeTxHash>

# Sign a pending transaction (prompts for Safe owner key)
yarn cli safe sign 0x5775afA796818ADA27b09FaF5c90d101f04eF600 <safeTxHash>

# Execute once threshold is met (prompts for executor key)
yarn cli safe execute 0x5775afA796818ADA27b09FaF5c90d101f04eF600 <safeTxHash>
```

### Hardware wallets

The CLI prepares transactions and sends them to the device for signing. The
device never broadcasts; after you confirm on the device, the CLI submits the
signature or signed transaction through the RPC / Safe Transaction Service.

Before running a hardware-wallet command:

1. Connect the device to this machine.
2. Unlock it and open the Ethereum app.
3. Verify the derived address on the first run.

```bash
# Ledger
yarn cli undelegate-all 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B --signer-mode ledger

# Trezor
yarn cli undelegate-all 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B --signer-mode trezor
```

Always test with `--dry-run` or on a mainnet fork first.

## Security

See [`docs/SECURITY.md`](docs/SECURITY.md).

- Private keys are read via a hidden terminal prompt, never from argv/env.
- Keys, wallet clients, and Safe kit references are wiped immediately after use.
- Every transaction is simulated before signing/broadcast.
- Close the terminal after sensitive operations.

## Multisig transaction sharing

When a Safe transaction is proposed, the CLI:

1. Proposes it to the Safe Transaction Service (so co-signers can sign in the
   Safe UI or via this CLI).
2. Writes a local JSON backup to `data/safe-txs/<safe>-<safeTxHash>.json`.

The **Safe Transaction Service is the authoritative source of truth**. The local
JSON backup is only a convenience and never contains private keys.

## Safe 1.1.1 note

The Safe at `0x5775afA796818ADA27b09FaF5c90d101f04eF600` is a Gnosis Safe
v1.1.1. The script prints a warning because v1.1.1 is behind the current LTS
(1.4.1/1.5.x) and has a known setup-time `delegatecall` issue reported by
OpenZeppelin in March 2020. Consider upgrading the Safe singleton before
high-value operations.

## Tests

```bash
yarn install            # Install dependencies
yarn build              # TypeScript typecheck
yarn lint               # ESLint
yarn test               # Unit tests + skipped fork tests
RPC_URL=https://... yarn test  # Includes mainnet fork integration tests
```

## License

Undecided. This repository is currently private and will be made public later.
See `LICENSE` for the placeholder status.
