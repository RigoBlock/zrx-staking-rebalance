# Mocks and Missing Information

This file lists every mock, placeholder, or unverified assumption in the code.

## ✅ Resolved

- **TupleFixer address** — now set to the real mainnet address
  `0x609abe9b2b09d1e2c2abfe93dfffd9f596d9a06e`.
- **ERC20 Asset Proxy** — now set to `0x95e6f48254609a6ee006f7d493c8e5fb97094cef`;
  ZRX staking approvals target this contract.
- **wZRX flow** — implemented with real mainnet addresses. It only wraps **liquid
  ZRX** (unstaked ERC-20 balance). It does **not** unstake or undelegate, so
  legacy staking voting power is preserved while the new wZRX position is built
  in parallel.
- **Safe Transaction Service is the source of truth** — proposals,
  confirmations, and execution are read from / written to the Safe Transaction
  Service. Local JSON backups are written to `data/safe-txs/` for convenience
  only.
- **`GITHUB_TOKEN` push removed** — the `--push-github` option and related
  GitHub backup code were removed. Use the Safe Transaction Service to share
  transactions between signers.
- **ESLint in CI** — `.github/workflows/test.yml` runs `yarn lint` on every push
  and PR.
- **Security audit (memory / signer lifecycle)** — see
  `docs/SECURITY_AUDIT.md`.

## ⚠️ Still to validate

### 1. Hardware wallets

**Location**: `src/ethereum/hardware.ts`

Ledger and Trezor wrappers use the official SDKs (`@ledgerhq/hw-app-eth`,
`@trezor/connect`) and create real viem custom accounts. They have not been
executed against physical devices in this repo. Before mainnet use:

- run a dry-run on a testnet or mainnet fork,
- verify the derivation path returns the expected address,
- verify the device prompts and signed transactions,
- make sure the device is unlocked and the Ethereum app is open before starting
  the command.

The CLI only **prepares and signs** transactions with the hardware device. It
**does not broadcast** from the device; after the device signs, the CLI sends
the signed transaction (or Safe signature) via the configured RPC / Safe
Transaction Service.

### 2. Safe on-chain verification

The CLI reads the Safe singleton version via the Safe SDK and warns on outdated
versions, but it does not yet enumerate or validate enabled modules/guards.

### 3. Gas-limit override

There is no `--gas-limit` override yet. Gas is estimated automatically and
reverts are caught during simulation.

### 4. Fourth target delegate

The 4th voting delegate's pool id and operator are unknown. The CLI accepts an
optional extra pool id:

```bash
yarn cli delegate-equal <wallet> <amount> <pool4-id>
```

### 5. Fork integration tests

**Location**: `tests/integration/fork.test.ts`

Fork tests are **skipped unless the `RPC_URL` environment variable is set**.
When run, they spin up a local anvil mainnet fork, seed a fresh test account
with ZRX (via ERC-20 storage override), stake it, delegate it, and advance the
staking epoch by overriding the staking contract's `currentEpoch` / start-time
storage slots. This gives the tests real on-chain state to exercise without
relying on any particular mainnet address holding a balance.

CI runs them automatically when the repository secret `RPC_URL` is configured.
