/**
 * Operation: migrate undelegated ZRX stake into wZRX governance.
 *
 * This flow unstakes ZRX that is already in the undelegated status and then
 * wraps it into wZRX. It does NOT undelegate — the caller must have run
 * `undelegate-all` and waited for the next epoch (or called `endEpoch()`)
 * before using this operation.
 *
 * GitHub source: src/operations/wrapGovernanceFromStake.ts
 */

import type { Address, PublicClient } from 'viem';
import {
  STAKING_PROXY_ADDRESS,
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  encodeApproveZrxToWzrx,
  encodeResetZrxApprovalForWzrx,
} from '../contracts/zrx.js';
import { encodeUnstake, readOwnerUndelegatedStake } from '../contracts/staking.js';
import { encodeDelegateWzrx, encodeWrapZrxFor } from '../contracts/wzrx.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planUnstakeAndWrapGovernance(
  publicClient: PublicClient,
  account: Address,
  amount: bigint,
  delegatee: Address
): Promise<OperationPlanResult> {
  const undelegated = await readOwnerUndelegatedStake(publicClient, account);
  const withdrawable =
    undelegated.currentEpochBalance < undelegated.nextEpochBalance
      ? undelegated.currentEpochBalance
      : undelegated.nextEpochBalance;

  if (withdrawable < amount) {
    throw new Error(
      `Insufficient undelegated stake to unstake: have ${formatZrx(
        withdrawable
      )}, need ${formatZrx(amount)}. ` +
        'Undelegate first and wait for the next epoch (or call endEpoch on the fork).'
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
      {
        to: ZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeApproveZrxToWzrx(amount),
        description: `Approve wZRX to spend ${formatZrx(amount)} ZRX`,
      },
      {
        to: WZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeWrapZrxFor(account, amount),
        description: `Wrap ${formatZrx(amount)} ZRX into wZRX for ${account}`,
      },
      {
        to: WZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeDelegateWzrx(delegatee),
        description: `Delegate wZRX voting power to ${delegatee}`,
      },
      {
        to: ZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeResetZrxApprovalForWzrx(),
        description: 'Reset ZRX approval to wZRX contract',
      },
    ],
    summary: `Unstake and wrap ${formatZrx(amount)} ZRX to wZRX (delegate to ${delegatee})`,
  };
}
