# Security Model

## Private-key handling

The script never accepts a private key from command-line arguments, environment
variables, or files. It is always collected via a hidden terminal prompt
(`securePrompt` in `src/utils/security.ts`).

### Memory lifecycle

1. The user types the key; characters are echoed as `*` and stored in a local
   string variable.
2. `privateKeyToAccount` consumes the string to build a viem `Account`.
3. The local string is overwritten via `wipeSecret` and the variable is allowed
   to go out of scope.
4. The viem `WalletClient` and `Account` references are dropped after use.
5. For Safe operations, the protocol-kit instance is dropped via
   `wipeKitReference` and not reused.

Because JavaScript strings are immutable, true memory scrubbing is not
guaranteed by the runtime. The best practical mitigation is:

- keep the secret in the narrowest scope possible,
- avoid closures that capture it,
- close the terminal process after signing.

## Hardware wallets

Ledger and Trezor support use the official Node.js SDKs
(`src/ethereum/hardware.ts`). The private key never leaves the device. These
paths should still be validated on a testnet or mainnet fork before mainnet use.

The CLI prepares transactions, sends them to the connected device for signing,
and then broadcasts the signed transaction (or Safe signature) through the RPC /
Safe Transaction Service. The device itself does not broadcast.

## Transaction simulation

Every EOA transaction is simulated with `publicClient.estimateGas` before
broadcast. Safe operations simulate each inner call from the Safe address
before proposing, and `protocolKit.isValidTransaction` is checked before
execution. A failing simulation aborts the flow before any signature is
produced.

## Safe Transaction Service

Proposed Safe transactions are shared via the official Safe Transaction Service.
A local JSON backup is also written to `data/safe-txs/` as a convenience, but
**the Safe Transaction Service is the authoritative source of truth**. These
backups never contain private keys.

## Audit status

A focused self-audit of memory cleanup and signer lifecycle is recorded in
`docs/SECURITY_AUDIT.md`. This is not a third-party audit. Use at your own risk,
preferably with a hardware wallet or a well-tested Safe multisig.
