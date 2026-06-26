# Governance Migration

The new 0x governance model uses a wrapped ZRX token (`wZRX`) that delegates
voting power to a chosen address. This project provides two migration paths.

## 1. Full legacy-stake migration (`wrap-governance`)

For ZRX that is currently staked/delegated in the legacy 0x staking system,
`wrap-governance` performs the complete migration in one command:

```bash
yarn cli wrap-governance <wallet> <amount> --delegatee <delegatee-address>
```

The planner builds the following sequence:

1. **Undelegate all** delegated stake via the Rigoblock TupleFixer.
2. **Assert** that `unstake(amount)` reverts before the epoch ends.
3. **Call `endEpoch()`** once the epoch has actually ended on-chain.
4. **Atomically** `unstake`, `approve(ZRX, wZRX, amount)`, `wZRX.depositFor`,
   `wZRX.delegate(delegatee)`, and reset the ZRX approval.

For Safe wallets the whole sequence is bundled into one Safe transaction. For
EOA wallets the transactions are sent sequentially.

The command will refuse to proceed if the staking epoch has not ended yet. On
mainnet you must wait until `currentEpochStartTimeInSeconds + epochDurationInSeconds`
has passed; anyone can then call `endEpoch()`.

## 2. Liquid-only wrap (`wrap-governance-liquid`)

If the ZRX is already unstaked and sitting in the wallet as ERC-20 balance,
use the liquid-only variant:

```bash
yarn cli wrap-governance-liquid <wallet> <amount> --delegatee <delegatee-address>
```

This does **not** undelegate or unstake anything. It only performs:

1. `approve(ZRX, wZRX, amount)`
2. `wZRX.depositFor(account, amount)`
3. `wZRX.delegate(delegatee)`
4. `approve(ZRX, wZRX, 0)`

## 3. Old treasury migration

The old 0x treasury at `0x0bb1810061c2f5b2088054ee184e6c79e1591101` holds
assets that can only be moved through passed governance proposals. To migrate
them to the new governance treasury (`ZeroExTreasuryGovernor` at
`0x4822cfc1e7699bdb9551bdfd3a838ee414bc2008`), first propose:

```bash
yarn cli treasury-migrate-propose <proposer-wallet> [--operated-pools <pool-id>...]
```

This creates a ZrxTreasury proposal whose actions move:

- all **ZRX**
- all **wCELO**
- all **MATIC** (approved to the Polygon migration contract, migrated 1:1 to
  **POL**, then transferred)

After the proposal passes and reaches its execution epoch, run:

```bash
yarn cli treasury-migrate-execute <wallet> <proposalId>
```

The proposer must have at least `proposalThreshold` voting power in the old
treasury. Pass any pools you operate with `--operated-pools`.

## Contracts

| Contract | Mainnet address |
|----------|-----------------|
| ZRX token | `0xE41d2489571d322189246DaFA5ebDe1F4699F498` |
| ZRXWrappedToken (wZRX) | `0xfcfaf7834f134f5146dbb3274bab9bed4bafa917` |
| ZeroExVotesProxy | `0x9c766e51b46cbc1fa4f8b6718ed4a60ac9d591fb` |
| Old ZRX Treasury | `0x0bb1810061c2f5b2088054ee184e6c79e1591101` |
| New governance treasury (ZeroExTreasuryGovernor) | `0x4822cfc1e7699bdb9551bdfd3a838ee414bc2008` |
| Polygon MATIC→POL migration | `0x29e7DF7b6A1B2b07b731457f499E1696c60E2C4e` |
| POL token | `0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6` |
| wCELO token | `0xe452e6ea2ddeb012e20db73bf5d3863a3ac8d77a` |
| MATIC token | `0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0` |
