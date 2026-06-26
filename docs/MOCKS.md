# Mocks and Missing Information

This file lists everything that is still mocked, unverified, or otherwise not
fully resolved.

## 1. Hardware wallets

**Location**: `src/ethereum/hardware.ts`

Ledger and Trezor wrappers use the official SDKs (`@ledgerhq/hw-app-eth`,
`@trezor/connect`) and create real viem custom accounts. They have not been
executed against physical devices in this repo.

Before mainnet use: run a dry-run on a fork, verify the derived address, and
confirm the device prompts and signed transactions.

## 2. Safe module/guard validation

The CLI reads the Safe singleton version via the Safe SDK and warns on outdated
versions, but it does not enumerate or validate enabled modules or guards.

## 3. Gas-limit override

There is no `--gas-limit` override. Gas is estimated automatically and reverts
are caught during simulation.

## 4. Fourth target delegate

The 4th voting delegate's pool id and operator are unknown. The CLI accepts an
optional extra pool id:

```bash
yarn cli delegate-equal <wallet> <amount> <pool4-id>
```

## 5. Fork integration tests

**Location**: `tests/integration/fork.test.ts`

Fork tests are skipped unless the `RPC_URL` environment variable is set. They
spin up a local anvil mainnet fork, seed a fresh test account with ZRX via
ERC-20 storage override, stake it, delegate it, and advance the staking epoch
by overriding the staking contract's `currentEpoch` / start-time storage slots.

CI runs them automatically when the repository secret `RPC_URL` is configured.
