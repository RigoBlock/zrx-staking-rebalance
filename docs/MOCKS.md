# Known Limitations and Unverified Components

This file lists parts of the codebase that have known limitations or have not
been executed against real mainnet state/hardware.

## 1. Hardware wallets

**Location**: `src/ethereum/hardware.ts`

Ledger and Trezor wrappers use the official SDKs (`@ledgerhq/hw-app-eth`,
`@trezor/connect`) and create real viem custom accounts. They have not been
executed against physical devices in this repo.

Before mainnet use: run a dry-run on a fork, verify the derived address, and
confirm the device prompts and signed transactions.

> Note: if the project later adopts Foundry scripts, EOA transactions can also
> be broadcast with hardware wallets via `cast send --ledger` or
> `forge script --broadcast --ledger`. The Safe multisig workflow still requires
> the Safe SDK or Transaction Service for proposing, collecting signatures, and
> executing.

## 2. Safe module/guard validation

The CLI reads the Safe singleton version via the Safe SDK and warns on outdated
versions, but it does not enumerate or validate enabled modules or guards.

## 3. Gas-limit override

There is no `--gas-limit` override. Gas is estimated automatically and reverts
are caught during simulation.
