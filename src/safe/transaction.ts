/**
 * Safe transaction lifecycle helpers.
 *
 * Uses @safe-global/protocol-kit and @safe-global/api-kit to create,
 * propose, list, confirm, and execute Safe transactions with minimal custom
 * encoding logic.
 *
 * GitHub source: src/safe/transaction.ts
 */

import { OperationType, type MetaTransactionData, type SafeTransaction } from '@safe-global/types-kit';
import type { Address, Hex, PublicClient } from 'viem';
import type { OperationPlan } from '../operations/types.js';
import { initSafeKitBundle, type SafeKitBundle } from './kit.js';
import { decodeSafeTransactionData } from './decoder.js';
import { info, printTxPreview, success, warning } from '../utils/format.js';
import { withRetry } from '../ethereum/retry.js';

export interface ProposedSafeTransaction {
  safeTxHash: Hex;
  safeAddress: Address;
  senderAddress: Address;
}

/** Convert one or more operation plans into Safe transaction inputs. */
export function plansToMetaTransactions(plans: OperationPlan[]): MetaTransactionData[] {
  return plans.map((plan) => ({
    to: plan.to,
    value: plan.value.toString(),
    data: plan.data,
    operation: OperationType.Call,
  }));
}

/** Create a single Safe transaction from operation plans. */
export async function createSafeTransaction(
  bundle: SafeKitBundle,
  plans: OperationPlan[]
): Promise<SafeTransaction> {
  const transactions = plansToMetaTransactions(plans);
  return bundle.protocolKit.createTransaction({ transactions });
}

/**
 * Simulate each inner call from the Safe address.
 * This catches reverts before the transaction is proposed.
 */
export async function simulateSafePlans(
  publicClient: PublicClient,
  safeAddress: Address,
  plans: OperationPlan[]
): Promise<void> {
  for (const plan of plans) {
    if (plan.skipSimulation) {
      info(`Skipping simulation for "${plan.description}" (depends on earlier bundle actions).`);
      continue;
    }
    try {
      await publicClient.call({
        account: safeAddress,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new Error(
        `Simulation failed for "${plan.description}": ${message}`,
        { cause: err }
      );
    }
  }
}

/** Propose a Safe transaction to the Safe Transaction Service. */
export async function proposeSafeTransaction(
  bundle: SafeKitBundle,
  safeAddress: Address,
  plans: OperationPlan[],
  origin = 'zrx-staking-rebalance'
): Promise<ProposedSafeTransaction> {
  const safeTransaction = await createSafeTransaction(bundle, plans);
  const signedTransaction = await bundle.protocolKit.signTransaction(safeTransaction);
  const safeTxHash = (await bundle.protocolKit.getTransactionHash(
    signedTransaction
  )) as Hex;
  const senderAddress = (await bundle.protocolKit.getAddress()) as Address;

  await withRetry(
    () =>
      bundle.apiKit.proposeTransaction({
        safeAddress,
        safeTransactionData: signedTransaction.data,
        safeTxHash,
        senderAddress,
        senderSignature: signedTransaction.encodedSignatures(),
        origin,
      }),
    { label: 'Safe API proposeTransaction' }
  );

  return { safeTxHash, safeAddress, senderAddress };
}

/** List pending Safe transactions. */
export async function listPendingSafeTransactions(
  bundle: SafeKitBundle,
  safeAddress: Address
) {
  const nonce = await bundle.protocolKit.getNonce();
  return withRetry(
    () => bundle.apiKit.getPendingTransactions(safeAddress, nonce),
    { label: 'Safe API getPendingTransactions' }
  );
}

/** Fetch a single Safe transaction from the Transaction Service. */
export async function getSafeTransaction(bundle: SafeKitBundle, safeTxHash: Hex) {
  return withRetry(() => bundle.apiKit.getTransaction(safeTxHash), {
    label: 'Safe API getTransaction',
  });
}

/** Sign a pending Safe transaction and push the signature to the service. */
export async function confirmSafeTransaction(
  bundle: SafeKitBundle,
  safeTxHash: Hex
): Promise<void> {
  const signature = await bundle.protocolKit.signHash(safeTxHash);
  await withRetry(
    () => bundle.apiKit.confirmTransaction(safeTxHash, signature.data),
    { label: 'Safe API confirmTransaction' }
  );
}

/**
 * Execute a fully signed Safe transaction.
 *
 * Before execution, prints a human-readable preview of the inner calls.
 */
export async function executeSafeTransaction(
  bundle: SafeKitBundle,
  safeTxHash: Hex,
  safeAddress: Address
) {
  const transaction = await withRetry(
    () => bundle.apiKit.getTransaction(safeTxHash),
    { label: 'Safe API getTransaction' }
  );

  printTxPreview('Safe transaction to execute', {
    safe: safeAddress,
    safeTxHash,
    to: transaction.to,
    value: transaction.value,
    data: transaction.data,
    confirmations: transaction.confirmations?.length ?? 0,
    threshold: transaction.confirmationsRequired,
  });

  const decoded = decodeSafeTransactionData(transaction.data as Hex, transaction.to as Address);
  if (decoded) {
    console.log('\nDecoded actions:');
    decoded.forEach((line, i) => console.log(`  ${i + 1}. ${line}`));
  }

  // Validate that the transaction will execute successfully.
  const isValid = await bundle.protocolKit.isValidTransaction(transaction);
  if (!isValid) {
    throw new Error('Safe transaction validation failed; will not execute.');
  }

  const result = await bundle.protocolKit.executeTransaction(transaction);
  if (result.hash) {
    success(`Executed Safe transaction: ${result.hash}`);
  } else {
    warning('executeTransaction did not return a hash; check the Safe service.');
  }
  return result;
}

/**
 * Initialize a Safe kit bundle with an optional signer. When the signer is
 * not provided the bundle is read-only (e.g. for listing transactions).
 */
export async function createSafeBundle(
  rpcUrl: string,
  safeAddress: Address,
  chainId: bigint,
  signer?: string,
  txServiceUrl?: string
): Promise<SafeKitBundle> {
  return initSafeKitBundle(rpcUrl, safeAddress, chainId, signer, txServiceUrl);
}
