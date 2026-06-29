# Governance Migration

The new 0x governance model uses a wrapped ZRX token (`wZRX`) that delegates
voting power to a chosen address. This project provides three migration paths.

## 1. Full legacy-stake migration (`wrap full`)

For ZRX that is currently staked/delegated in the legacy 0x staking system:

```bash
yarn op:wrap full <staker> <delegatee> <amount>
```

Or interactively:

```bash
yarn op
# choose wrap → full
```

The script performs:

1. **Undelegate all** delegated stake.
2. **Advance the epoch** and call `endEpoch()`.
3. **Atomically** `unstake(amount)`, `approve(ZRX, wZRX, amount)`,
   `wZRX.depositFor(staker, amount)`, `wZRX.delegate(delegatee)`, and reset the
   ZRX approval.

Simulate first:

```bash
yarn op:sim:wrap full <staker> <delegatee> <amount>
```

## 2. Liquid-only wrap (`wrap liquid`)

If the ZRX is already unstaked and sitting in the wallet as ERC-20 balance:

```bash
yarn op:wrap liquid <staker> <delegatee> <amount>
```

This only performs:

1. `approve(ZRX, wZRX, amount)`
2. `wZRX.depositFor(staker, amount)`
3. `wZRX.delegate(delegatee)`
4. `approve(ZRX, wZRX, 0)`

## 3. Exclude-pools wrap (`wrap exclude-pools`)

To keep some pools delegated while moving the rest to wZRX:

```bash
yarn op:wrap exclude-pools <staker> <delegatee> <amount> \
  <pool-to-exclude>...
```

The script undelegates from every pool except the excluded ones, advances the
epoch, calls `endEpoch()`, unstakes the requested amount, then wraps and
delegates it.

## 4. Old treasury migration

The old 0x treasury at `0x0bb1810061c2f5b2088054ee184e6c79e1591101` holds
assets that can only be moved through passed governance proposals. To migrate
them to the new governance treasury (`ZeroExTreasuryGovernor` at
`0x4822cfc1e7699bdb9551bdfd3a838ee414bc2008`), first propose:

```bash
yarn op:treasury propose <proposer> [<operated-pool>...]
```

This creates a ZrxTreasury proposal whose actions move:

- all **ZRX**
- all **wCELO**
- all **MATIC** (approved to the Polygon migration contract, migrated 1:1 to
  **POL**, then transferred)

After the proposal passes and reaches its execution epoch, run:

```bash
yarn op:treasury execute <proposer> <proposalId>
```

The proposer must have at least `proposalThreshold` voting power in the old
treasury. Pass any operated pools when proposing.

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
