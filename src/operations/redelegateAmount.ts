/**
 * Operation: rebalance delegated stake so the target pools end with exactly a
 * requested total amount.
 *
 * - If the target pools are already at the requested total, nothing happens.
 * - If the target pools hold less than requested, stake is moved from
 *   non-target pools into the target pools.
 * - If the target pools hold more than requested, the excess is moved to the
 *   undelegated bucket.
 *
 * GitHub source: src/operations/redelegateAmount.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { resolveTargetPools } from '../config/pools.js';
import {
  buildRebalanceCalldata,
  buildScaledUndelegation,
  encodeBatchExecute,
  fetchDelegatedPoolBalances,
  type DelegatedPoolBalance,
} from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export interface RedelegateAmountResult {
  result: OperationPlanResult;
  targetAmount: bigint;
  currentTargetAmount: bigint;
  movedAmount: bigint;
  innerCalls: Hex[];
}

export async function planRedelegateAmount(
  publicClient: PublicClient,
  staker: Address,
  targetAmount: bigint,
  targetPoolIds: Hex[] = resolveTargetPools()
): Promise<RedelegateAmountResult> {
  if (targetAmount < 0n) {
    throw new Error('targetAmount must be non-negative');
  }
  if (targetPoolIds.length === 0) {
    throw new Error('At least one target pool is required');
  }

  const allBalances = await fetchDelegatedPoolBalances(publicClient, staker);
  const targetSet = new Set(targetPoolIds.map((id) => id.toLowerCase()));

  const targetBalances: DelegatedPoolBalance[] = [];
  const nonTargetBalances: DelegatedPoolBalance[] = [];
  for (const b of allBalances) {
    if (targetSet.has(b.poolId.toLowerCase())) {
      targetBalances.push(b);
    } else {
      nonTargetBalances.push(b);
    }
  }

  const currentTargetAmount = targetBalances.reduce((a, b) => a + b.amount, 0n);

  if (targetAmount === currentTargetAmount) {
    return {
      result: {
        plans: [],
        summary: `Target pools already total ${formatZrx(targetAmount)} ZRX; no action needed`,
      },
      targetAmount,
      currentTargetAmount,
      movedAmount: 0n,
      innerCalls: [],
    };
  }

  let encodedCalls: Hex[];
  let movedAmount: bigint;
  let summary: string;

  if (targetAmount > currentTargetAmount) {
    movedAmount = targetAmount - currentTargetAmount;
    const nonTargetTotal = nonTargetBalances.reduce((a, b) => a + b.amount, 0n);
    if (movedAmount > nonTargetTotal) {
      throw new Error(
        `Cannot increase target pools to ${formatZrx(targetAmount)}: only ${formatZrx(
          nonTargetTotal
        )} available in non-target pools`
      );
    }
    const rebalance = buildRebalanceCalldata(
      nonTargetBalances,
      targetPoolIds,
      movedAmount
    );
    encodedCalls = rebalance.encodedCalls;
    summary = `Move ${formatZrx(movedAmount)} ZRX from non-target pools into target pools (new total ${formatZrx(
      targetAmount
    )})`;
  } else {
    movedAmount = currentTargetAmount - targetAmount;
    const undelegation = buildScaledUndelegation(targetBalances, movedAmount);
    encodedCalls = undelegation.encodedCalls;
    summary = `Undelegate ${formatZrx(movedAmount)} ZRX from target pools to reach ${formatZrx(
      targetAmount
    )} total`;
  }

  const data = encodedCalls.length > 0 ? encodeBatchExecute(encodedCalls) : '0x';

  return {
    result: {
      plans:
        encodedCalls.length > 0
          ? [
              {
                to: STAKING_PROXY_ADDRESS,
                value: 0n,
                data,
                description: summary,
              },
            ]
          : [],
      summary,
    },
    targetAmount,
    currentTargetAmount,
    movedAmount,
    innerCalls: encodedCalls,
  };
}
