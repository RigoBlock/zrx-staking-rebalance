# Security notes

Date: 2026-06-26  
Scope: Foundry scripts (`script/*.s.sol`), the interactive runner
(`sh/op.sh`), shell wrappers, `sh/safe-propose.sh`, and `sh/safe-confirm.sh`.

## Current architecture

- Operation logic lives in Solidity and is executed by `forge script`.
- The interactive runner (`sh/op.sh`) only collects parameters and spawns the
  appropriate shell wrapper; it does not build transactions itself.
- Private keys are either prompted interactively (hidden) or supplied via the
  `PRIVATE_KEY` environment variable for the lifetime of the forge subprocess.
- Safe proposals are built with `script/SafeTx.s.sol` and posted via
  `sh/safe-propose.sh` using `cast wallet sign` and `curl`.
- Additional Safe signatures are added via `sh/safe-confirm.sh` or the Safe UI.
- Execution happens in the Safe UI once the threshold is reached.
- There is no custom Safe singleton version check; the Safe UI warns users when
  a singleton upgrade is advisable.
- Hardware wallets are handled natively by Foundry (`--ledger`, `--trezor`).

## Key handling

- The runner never logs the private key.
- When using `PRIVATE_KEY`, the variable is passed to the child process and
  dropped when the process exits.
- Process environment variables are not scrubbed by the runtime. Close the
  terminal after high-value operations.

## Simulation

- Every operation can be simulated first via `yarn op:sim:*` or the
  "Simulate" option in `yarn op`.
- Forge runs the script without broadcasting; reverts are reported before any
  signature is produced.

## Hardware wallets

- Ledger/Trezor paths have not been executed against physical devices in this
  repo.
- Before mainnet use, validate the derived address and transaction details on
  the device screen during a mainnet-fork simulation.

## Recommendations

1. Run `yarn test:foundry` (requires `RPC_URL`) before any mainnet operation.
2. Use a hardware wallet or well-tested Safe multisig for production.
3. Do not run operations in an environment where untrusted processes can read
   the terminal or process memory.
4. After sensitive operations, close the terminal session.
