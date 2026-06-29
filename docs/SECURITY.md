# Security Model

## Private-key handling

The interactive runner (`yarn op`) never accepts a private key from command-line
arguments or files. It is collected via a hidden terminal prompt and passed to
the Foundry script through the `PRIVATE_KEY` environment variable only for the
lifetime of the subprocess. The key is never logged or persisted.

For scripted usage you can also export `PRIVATE_KEY` yourself and call a shell
wrapper directly:

```bash
PRIVATE_KEY=0x... yarn op:stake-delegate 0x... 1000
```

Hardware-wallet signers (`LEDGER=1`, `TREZOR=1`) and Foundry mnemonic accounts
(`MNEMONIC_INDEX`) are also supported; the secret never leaves the device or
Foundry's signer logic.

## Memory lifecycle

- The key is typed into the interactive prompt as `*` and exported as
  `PRIVATE_KEY` only for the lifetime of the forge subprocess.
- When the subprocess exits, the environment variable is dropped.
- Close the terminal process after signing high-value operations.

Keep the secret in the narrowest scope possible and use a hardware wallet for
production operations.

## Hardware wallets

Ledger and Trezor are supported natively by Foundry (`--ledger`, `--trezor`).
The private key never leaves the device. Test on a mainnet fork first and
verify the derived address and transaction details on the device screen.

## Transaction simulation

Every operation should be simulated before broadcast:

```bash
yarn op:sim:stake-delegate 0x... 1000
```

The `op:sim:*` scripts set `DRY_RUN=1`, so Foundry runs the script without
broadcasting. The interactive `yarn op` runner also offers a "Simulate" mode.

## Safe Transaction Service

Safe transactions are proposed with `sh/safe-propose.sh` and confirmed with
`sh/safe-confirm.sh`. They follow the same pattern 0x Settler uses:

- The Safe transaction hash is computed by calling the Safe contract with
  `cast call getTransactionHash(...)`.
- The hash is signed with `cast wallet sign --no-hash`.
- The signed payload is POSTed to the Safe Transaction Service URL defined in
  `sh/constants.sh` (mainnet only).

No Safe SDK or Node runtime is involved; the flow is pure Foundry/shell.

For hardware wallets, sign the `safeTxHash` offline with `cast wallet sign --no-hash`
and pass `--signature <sig> --sender <owner>` to the scripts.

The plan JSON written by `WRITE_PLAN=1` is a local convenience artifact and never
contains private keys.

## Audit status

This is not a third-party audit. Use at your own risk, preferably with a
hardware wallet or a well-tested Safe multisig.
