# Security audit: memory cleanup and signer lifecycle

Date: 2026-06-26
Scope: private-key handling, hardware wallet signer lifecycle, EOA wallet client
cleanup, Safe protocol-kit / API-kit cleanup, transaction simulation ordering.

## Findings and fixes

### 1. Private-key prompt scope (FIXED)

Private keys are read only through `securePrompt` in `src/utils/security.ts`.
The terminal is put into raw mode so characters are not echoed. The key is
returned as a string, used immediately to build a viem `Account`, and the local
string reference is passed to `wipeSecret`.

Remaining risk: JavaScript strings are immutable, so `wipeSecret` can only
remove the local reference. The actual bytes may remain in the JS heap until
garbage collection. Mitigation: keep the variable in the narrowest scope and
exit the process after signing.

### 2. Safe signer key leak (FIXED)

In `src/cli.ts` `runOperation` the Safe owner private key was captured in
`safeSignerKey`, passed to `createSafeBundle`, but never explicitly wiped after
the `finally` block. The `finally` block now calls `wipeSecret(safeSignerKey)`.

### 3. Kit reference cleanup (FIXED)

`wipeKitReference` previously reassigned its local parameter to `null`, which
did not mutate the caller's object. It now iterates the bundle's enumerable
keys and sets each property to `undefined`. Callers additionally assign their
own variable to `undefined` after the call.

### 4. Account reference cleanup (FIXED)

`wipeSignerReference` was a no-op. It now nulls enumerable properties of the
passed account / wallet client object. This makes the cleanup step explicit and
removes direct references to the account object from the caller's copy.

### 5. EOA wallet client lifecycle (FIXED)

`runOperation` for EOA wallets now keeps `walletClient`, `account`, and
cleanup` inside a narrow `try`/`finally` block and calls the cleanup callback.
The variables fall out of scope after the block, allowing garbage collection.

### 6. Hardware wallet UX (DOCUMENTED)

Ledger and Trezor signers in `src/ethereum/hardware.ts` create real viem custom
accounts backed by the device SDKs. The private key never leaves the device.
Before mainnet use operators must:

- unlock the device and open the Ethereum app before running the command,
- verify the derivation path returns the expected address on the first run,
- review each transaction on the device screen before confirming,
- run a dry-run / mainnet fork test first.

The CLI does not broadcast from the device; it sends prepared transactions to
the device for signature and then submits the signature / signed transaction
via the configured RPC or Safe Transaction Service.

### 7. Simulation before signature (OK)

For EOA transactions `publicClient.estimateGas` is called before signing. For
Safe transactions `simulateSafePlans` runs `eth_call` for each inner call from
the Safe address before the owner signs the proposal. `protocolKit.isValidTransaction`
is called before execution. Reverts are caught before any private key or device
signature is produced.

### 8. TupleFixer `msg.sender` bug (FIXED)

`fetchUndelegateAllCalldata` in `src/contracts/tupleFixer.ts` did not pass the
staker address to `publicClient.readContract`. The mainnet TupleFixer contract
reads `msg.sender` to know whose stake to undelegate, so it always returned an
empty result. The staker address is now passed as the `account` option so the
view call uses the correct `msg.sender`.

### 8. Safe Transaction Service as source of truth (OK)

The `--push-github` backup path that required `GITHUB_TOKEN` was removed. Safe
transactions are proposed, confirmed, and executed through the Safe Transaction
Service. Local JSON backups in `data/safe-txs/` are a convenience only and never
contain private keys.

## Recommendations

1. Run fork integration tests (`RPC_URL` required) before any mainnet operation.
2. Validate hardware wallet flows on a mainnet fork with real devices before
   mainnet use.
3. Do not run this CLI in an environment where other untrusted processes can
   read the terminal or process memory.
4. After sensitive operations, close the terminal session.
