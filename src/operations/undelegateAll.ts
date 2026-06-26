/**
 * Operation: undelegate all currently delegated stake.
 *
 * Uses the Rigoblock TupleFixer helper at 0x609abe9b2b09d1e2c2abfe93dfffd9f596d9a06e.
 *
 * GitHub source: src/operations/undelegateAll.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { fetchUndelegateAllCalldata } from '../contracts/tupleFixer.js';
import { encodeBatchExecute } from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export interface UndelegateAllResult {
  result: OperationPlanResult;
  totalUndelegatedAmount: bigint;
  innerCalls: Hex[];
}

export async function planUndelegateAll(
  publicClient: PublicClient,
  staker: Address
): Promise<UndelegateAllResult> {
  const { totalUndelegatedAmount, encodedCalls } = await fetchUndelegateAllCalldata(
    publicClient,
    staker
  );

  if (encodedCalls.length === 0) {
    throw new Error('No delegated stake found to undelegate');
  }

  const data = encodeBatchExecute(encodedCalls);

  return {
    result: {
      plans: [
        {
          to: STAKING_PROXY_ADDRESS,
          value: 0n,
          data,
          description: `Undelegate all stake (${formatZrx(
            totalUndelegatedAmount
          )} ZRX) from ${encodedCalls.length} active delegation(s)`,
        },
      ],
      summary: `Undelegate ${formatZrx(totalUndelegatedAmount)} ZRX`,
    },
    totalUndelegatedAmount,
    innerCalls: encodedCalls,
  };
}
