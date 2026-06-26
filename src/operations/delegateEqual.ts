/**
 * Operation: delegate an aggregate ZRX amount equally across target pools.
 *
 * GitHub source: src/operations/delegateEqual.ts
 */

import type { Hex, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { encodeBatchExecute, encodeEqualDelegation } from '../contracts/staking.js';
import { formatAllocations, formatZrx, parseZrx, splitEqually, validateSplit } from '../utils/amounts.js';
import type { Address } from 'viem';
import type { OperationPlanResult } from './types.js';

export async function planDelegateEqual(
  _publicClient: PublicClient,
  _staker: Address,
  amount: bigint,
  poolIds: Hex[]
): Promise<OperationPlanResult> {
  if (poolIds.length === 0) {
    throw new Error('At least one target pool is required');
  }

  const allocations = splitEqually(amount, poolIds.length);
  validateSplit(allocations, amount);

  const delegateCalls = encodeEqualDelegation(poolIds, allocations);
  const data =
    delegateCalls.length === 1
      ? delegateCalls[0]
      : encodeBatchExecute(delegateCalls);

  return {
    plans: [
      {
        to: STAKING_PROXY_ADDRESS,
        value: 0n,
        data,
        description: `Delegate ${formatZrx(amount)} ZRX equally across ${
          poolIds.length
        } pools:\n${formatAllocations(poolIds, allocations)}`,
      },
    ],
    summary: `Delegate ${formatZrx(amount)} ZRX across ${poolIds.length} pools`,
  };
}

export { parseZrx, formatZrx };
