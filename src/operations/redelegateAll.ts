/**
 * Operation: undelegate all active stake and redelegate it equally across a
 * set of target pools.
 *
 * This is useful when the active stake is currently spread across pools that
 * are no longer part of the target set and the caller wants to consolidate it.
 *
 * GitHub source: src/operations/redelegateAll.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { resolveTargetPools } from '../config/pools.js';
import {
  buildRebalanceCalldata,
  encodeBatchExecute,
  fetchDelegatedPoolBalances,
} from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export interface RedelegateAllResult {
  result: OperationPlanResult;
  totalRedelegatedAmount: bigint;
  innerCalls: Hex[];
}

export async function planRedelegateAll(
  publicClient: PublicClient,
  staker: Address,
  targetPoolIds: Hex[] = resolveTargetPools()
): Promise<RedelegateAllResult> {
  const sourceBalances = await fetchDelegatedPoolBalances(publicClient, staker);
  const totalRedelegatedAmount = sourceBalances.reduce((a, b) => a + b.amount, 0n);

  if (totalRedelegatedAmount === 0n) {
    throw new Error('No delegated stake found to redelegate');
  }
  if (targetPoolIds.length === 0) {
    throw new Error('At least one target pool is required');
  }

  const { encodedCalls } = buildRebalanceCalldata(
    sourceBalances,
    targetPoolIds,
    totalRedelegatedAmount
  );

  const data = encodeBatchExecute(encodedCalls);
  const summary = `Redelegate ${formatZrx(totalRedelegatedAmount)} ZRX to ${targetPoolIds.length} target pools`;

  return {
    result: {
      plans: [
        {
          to: STAKING_PROXY_ADDRESS,
          value: 0n,
          data,
          description: summary,
        },
      ],
      summary,
    },
    totalRedelegatedAmount,
    innerCalls: encodedCalls,
  };
}
