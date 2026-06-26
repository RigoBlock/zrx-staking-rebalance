/**
 * Operation: unstake ZRX from the 0x staking contract.
 *
 * Stake must be in the undelegated status in both the current and next epoch.
 * Use `undelegate-all` first and wait for the next epoch before unstaking.
 *
 * GitHub source: src/operations/unstake.ts
 */

import type { Address, PublicClient } from 'viem';
import { STAKING_PROXY_ADDRESS } from '../config/constants.js';
import { encodeUnstake, readOwnerUndelegatedStake } from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planUnstake(
  publicClient: PublicClient,
  staker: Address,
  amount: bigint
): Promise<OperationPlanResult> {
  const undelegated = await readOwnerUndelegatedStake(publicClient, staker);
  const withdrawable =
    undelegated.currentEpochBalance < undelegated.nextEpochBalance
      ? undelegated.currentEpochBalance
      : undelegated.nextEpochBalance;

  if (withdrawable < amount) {
    throw new Error(
      `Insufficient undelegated stake to unstake: have ${formatZrx(
        withdrawable
      )}, need ${formatZrx(amount)}. ` +
        'Undelegate first and wait for the next epoch.'
    );
  }

  return {
    plans: [
      {
        to: STAKING_PROXY_ADDRESS,
        value: 0n,
        data: encodeUnstake(amount),
        description: `Unstake ${formatZrx(amount)} ZRX`,
      },
    ],
    summary: `Unstake ${formatZrx(amount)} ZRX`,
  };
}
