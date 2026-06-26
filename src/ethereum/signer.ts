/**
 * EOA signer creation with secure private-key handling.
 *
 * The private key is accepted only via a hidden terminal prompt, used inside
 * a narrow scope, and every reference is wiped immediately after signing.
 *
 * GitHub source: src/ethereum/signer.ts
 */

import { privateKeyToAccount, type Account } from 'viem/accounts';
import { securePrompt, wipeSecret, wipeSignerReference } from '../utils/security.js';
import type { Address } from 'viem';

/**
 * Prompt for a private key and return a viem account.
 *
 * SECURITY: The caller is responsible for:
 *   - using the account only in a narrow scope,
 *   - calling `wipeEoaSigner(account)` when done,
 *   - not capturing the private key in closures or logs.
 */
export async function promptForEoaAccount(): Promise<Account> {
  const key = await securePrompt('Enter private key (0x...)');
  if (!key.startsWith('0x') || key.length !== 66) {
    wipeSecret(key);
    throw new Error('Private key must be a 32-byte hex string starting with 0x');
  }
  try {
    const account = privateKeyToAccount(key as `0x${string}`);
    wipeSecret(key);
    return account;
  } catch (err) {
    wipeSecret(key);
    throw new Error(
      `Invalid private key: ${err instanceof Error ? err.message : err}`,
      { cause: err }
    );
  }
}

/**
 * Overwrite the local reference to an account and clear viem caches.
 *
 * Because viem stores the private key in a closure inside the account object,
 * dropping all references is the best we can do in JS.
 */
export function wipeEoaAccount(account: Account | undefined): void {
  if (!account) return;
  wipeSignerReference(account);
  // Reassigning the parameter does not affect the caller, so callers must
  // additionally assign their own variable to undefined.
}

/** Derive the address from a private key without persisting the account. */
export async function previewAddressFromPrivateKey(): Promise<Address> {
  const account = await promptForEoaAccount();
  const address = account.address;
  wipeEoaAccount(account);
  return address;
}
