/**
 * Operation: atomically undelegate all stake and redelegate equally.
 *
 * Uses StakingProxy.batchExecute to combine the calls in a single
 * transaction.
 *
 * GitHub source: src/operations/undelegateAndDelegate.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { encodeBatchExecute, encodeEqualDelegation } from '../contracts/staking.js';
import { fetchUndelegateAllCalldata } from '../contracts/tupleFixer.js';
import { formatAllocations, formatZrx, splitEqually, validateSplit } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export interface UndelegateAndDelegateResult {
  result: OperationPlanResult;
  totalUndelegatedAmount: bigint;
  poolIds: Hex[];
  allocations: bigint[];
}

export async function planUndelegateAndDelegate(
  publicClient: PublicClient,
  staker: Address,
  amount: bigint,
  poolIds: Hex[]
): Promise<UndelegateAndDelegateResult> {
  if (poolIds.length === 0) {
    throw new Error('At least one target pool is required');
  }

  const { totalUndelegatedAmount, encodedCalls: undelegateCalls } =
    await fetchUndelegateAllCalldata(publicClient, staker);

  if (undelegateCalls.length === 0) {
    throw new Error('No delegated stake found to undelegate');
  }

  const allocations = splitEqually(amount, poolIds.length);
  validateSplit(allocations, amount);

  const delegateCalls = encodeEqualDelegation(poolIds, allocations);
  const allCalls = [...undelegateCalls, ...delegateCalls];

  const data = encodeBatchExecute(allCalls);

  return {
    result: {
      plans: [
        {
          to: STAKING_PROXY_ADDRESS,
          value: 0n,
          data,
          description:
            `Undelegate ${formatZrx(totalUndelegatedAmount)} ZRX from all pools, ` +
            `then delegate ${formatZrx(amount)} ZRX equally across ${
              poolIds.length
            } pools:\n${formatAllocations(poolIds, allocations)}`,
        },
      ],
      summary: `Undelegate all + delegate ${formatZrx(amount)} ZRX`,
    },
    totalUndelegatedAmount,
    poolIds,
    allocations,
  };
}
