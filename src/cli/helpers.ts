/**
 * CLI helpers: wallet resolution, transaction execution, simulation, Safe detection,
 * and local Safe transaction backups.
 *
 * GitHub source: src/cli/helpers.ts
 */

import type { Account, Address, Hex, PublicClient, WalletClient } from 'viem';
import { mainnet } from 'viem/chains';
import { SAFE_WALLET_ADDRESS } from '../config/constants.js';
import { createWalletClientForAccount, waitForReceipt } from '../ethereum/client.js';
import { createLedgerAccount, createTrezorAccount } from '../ethereum/hardware.js';
import { promptForEoaAccount, wipeEoaAccount } from '../ethereum/signer.js';
import type { OperationPlan } from '../operations/types.js';
import { error, info, success, warning } from '../utils/format.js';
import { wipeSecret } from '../utils/security.js';
import type { SignerMode } from '../types.js';
import * as fs from 'node:fs';
import * as path from 'node:path';

export interface ResolvedWallet {
  address: Address;
  isSafe: boolean;
}

export async function resolveWallet(
  publicClient: PublicClient,
  input: string,
  forceSafe = false
): Promise<ResolvedWallet> {
  const address = input.toLowerCase() as Address;
  if (forceSafe) return { address, isSafe: true };
  if (address.toLowerCase() === SAFE_WALLET_ADDRESS.toLowerCase()) {
    return { address, isSafe: true };
  }
  const bytecode = await publicClient.getBytecode({ address });
  return { address, isSafe: (bytecode?.length ?? 0) > 2 };
}

export async function loadSigner(
  mode: SignerMode,
  rpcUrl: string
): Promise<{ walletClient: WalletClient; account: Account; cleanup: () => void }> {
  switch (mode) {
    case 'private-key': {
      const account = await promptForEoaAccount();
      const walletClient = createWalletClientForAccount(rpcUrl, account);
      return {
        walletClient,
        account,
        cleanup: () => {
          wipeEoaAccount(account);
          wipeSecret(undefined);
        },
      };
    }
    case 'ledger': {
      const account = await createLedgerAccount();
      const walletClient = createWalletClientForAccount(rpcUrl, account);
      return {
        walletClient,
        account,
        cleanup: () => {
          wipeEoaAccount(account);
        },
      };
    }
    case 'trezor': {
      const account = await createTrezorAccount();
      const walletClient = createWalletClientForAccount(rpcUrl, account);
      return {
        walletClient,
        account,
        cleanup: () => {
          wipeEoaAccount(account);
        },
      };
    }
    case 'safe':
      throw new Error(
        'Safe wallets do not use a local signer. Use the safe subcommands instead.'
      );
  }
}

/**
 * Simulate a transaction from an EOA or Safe address.
 * Returns the gas estimate and reverts with a decoded message on failure.
 */
export async function simulateCall(
  publicClient: PublicClient,
  from: Address,
  plan: OperationPlan
): Promise<bigint> {
  try {
    const gas = await publicClient.estimateGas({
      account: from,
      to: plan.to,
      value: plan.value,
      data: plan.data,
    });
    info(`Simulation OK (gas estimate: ${gas.toString()})`);
    return gas;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(`Simulation failed for "${plan.description}": ${message}`, {
      cause: err,
    });
  }
}

export async function sendEoaTransaction(
  walletClient: WalletClient,
  account: Account,
  publicClient: PublicClient,
  plan: OperationPlan,
  dryRun: boolean
): Promise<Hex | undefined> {
  info(`Transaction preview:\n  to: ${plan.to}\n  value: ${plan.value.toString()}\n  data: ${plan.data}`);

  const gas = await simulateCall(publicClient, account.address, plan);

  if (dryRun) {
    warning('Dry-run enabled: transaction not sent.');
    return undefined;
  }

  const hash = await walletClient.sendTransaction({
    account,
    to: plan.to,
    value: plan.value,
    data: plan.data,
    chain: mainnet,
    gas,
  });

  success(`Transaction broadcast: ${hash}`);
  const receipt = await waitForReceipt(publicClient, hash);
  if (receipt.status === 'success') {
    success(`Transaction confirmed in block ${receipt.blockNumber.toString()}`);
  } else {
    error('Transaction reverted on-chain');
    throw new Error('Transaction reverted');
  }
  return hash;
}

export function printOperationPlans(plans: OperationPlan[]): void {
  info(`Planned actions (${plans.length} transaction(s)):`);
  plans.forEach((plan, i) => {
    console.log(`\n[${i + 1}] ${plan.description}`);
    console.log(`      to: ${plan.to}`);
    console.log(`      data: ${plan.data}`);
  });
}

/**
 * Save a Safe transaction proposal to a local JSON file as a fallback
 * sharing mechanism. Never stores private keys.
 */
export function saveSafeProposalBackup(
  safeAddress: Address,
  safeTxHash: Hex,
  plans: OperationPlan[]
): string {
  const dir = path.join(process.cwd(), 'data', 'safe-txs');
  fs.mkdirSync(dir, { recursive: true });
  const filename = `${safeAddress}-${safeTxHash}.json`;
  const filepath = path.join(dir, filename);
  const payload = {
    safeAddress,
    safeTxHash,
    createdAt: new Date().toISOString(),
    transactions: plans.map((p) => ({
      to: p.to,
      value: p.value.toString(),
      data: p.data,
      description: p.description,
    })),
  };
  fs.writeFileSync(filepath, JSON.stringify(payload, null, 2));
  return filepath;
}

