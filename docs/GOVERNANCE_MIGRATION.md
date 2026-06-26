# Governance Migration Bonus (wZRX)

The new 0x governance model uses a wrapped ZRX token (`wZRX`) that delegates
voting power to a chosen address.

## Design choice: keep legacy voting power intact

`wrap-governance` only wraps **liquid ZRX** — ZRX that is already unstaked and
sitting in the wallet as ERC-20 balance. It **does not** undelegate or unstake
from the legacy 0x staking system. This keeps the treasury's existing voting
power in the legacy pools during the migration while a parallel wZRX position is
built.

If you need to free ZRX that is currently staked, use the normal flow first:

```bash
yarn cli undelegate-all <wallet> --dry-run
# remove --dry-run and execute, then wait for the next epoch
yarn cli unstake <wallet> <amount>
```

After the ZRX is liquid you can wrap it:

```bash
yarn cli wrap-governance <wallet> <amount> --delegatee <delegatee-address>
```

## Implemented terminal flow

For the liquid amount requested, `wrap-governance` builds:

1. `approve(ZRX, wZRX, amount)`
2. `wZRX.depositFor(account, amount)`
3. `wZRX.delegate(delegatee)`
4. `approve(ZRX, wZRX, 0)` (reset allowance)

For EOA wallets these are sent as sequential transactions. For Safe wallets they
are combined into a single Safe transaction via MultiSend.

## Contracts

| Contract | Mainnet address |
|----------|-----------------|
| ZRX token | `0xE41d2489571d322189246DaFA5ebDe1F4699F498` |
| ZRXWrappedToken (wZRX) | `0xfcfaf7834f134f5146dbb3274bab9bed4bafa917` |
| ZeroExVotesProxy | `0x9c766e51b46cbc1fa4f8b6718ed4a60ac9d591fb` |

## Example

```bash
yarn cli wrap-governance 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000 \
  --delegatee 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B
```
