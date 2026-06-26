/**
 * Operation: full legacy-stake → wZRX governance migration.
 *
 * This planner performs the entire flow in one command:
 *   1. Undelegate all currently delegated stake.
 *   2. Confirm that `unstake(amount)` reverts before the epoch ends.
 *   3. Call `endEpoch()` to make the undelegated stake withdrawable.
 *   4. Atomically unstake, approve wZRX, wrap, delegate, and reset approval.
 *
 * For Safe wallets the whole sequence is bundled into a single Safe tx. For
 * EOA wallets it is executed as sequential transactions.
 *
 * GitHub source: src/operations/wrapGovernance.ts
 */

import type { Address, PublicClient } from 'viem';
import {
  STAKING_PROXY_ADDRESS,
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  encodeEndEpoch,
  encodeUnstake,
  readEpochInfo,
  readOwnerStakeStatuses,
} from '../contracts/staking.js';
import {
  encodeApproveZrxToWzrx,
  encodeResetZrxApprovalForWzrx,
} from '../contracts/zrx.js';
import { encodeDelegateWzrx, encodeWrapZrxFor } from '../contracts/wzrx.js';
import { planUndelegateAll } from './undelegateAll.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlan, OperationPlanResult } from './types.js';

/** Minimum number of seconds to pad past the epoch end before calling endEpoch. */
const END_EPOCH_PADDING_SECONDS = 60n;

async function assertUnstakeReverts(
  publicClient: PublicClient,
  account: Address,
  amount: bigint,
  description: string
): Promise<void> {
  try {
    await publicClient.estimateGas({
      account,
      to: STAKING_PROXY_ADDRESS,
      value: 0n,
      data: encodeUnstake(amount),
    });
  } catch {
    // Expected: unstake should revert because the epoch has not ended.
    return;
  }
  throw new Error(
    `Pre-condition failed: "${description}" simulated successfully, but it should revert before the epoch ends.`
  );
}

export async function planWrapGovernance(
  publicClient: PublicClient,
  account: Address,
  amount: bigint,
  delegatee: Address
): Promise<OperationPlanResult> {
  const [epochInfo, { delegated, undelegated }] = await Promise.all([
    readEpochInfo(publicClient),
    readOwnerStakeStatuses(publicClient, account),
  ]);

  const totalStaked = delegated.currentEpochBalance + undelegated.currentEpochBalance;
  if (amount > totalStaked) {
    throw new Error(
      `Insufficient staked ZRX to wrap: have ${formatZrx(
        totalStaked
      )} staked, want ${formatZrx(amount)}. Use wrap-governance-liquid for unstaked ZRX.`
    );
  }

  if (delegated.currentEpochBalance === 0n) {
    throw new Error(
      'No delegated ZRX to migrate. Use wrap-governance-liquid if you already have unstaked ZRX.'
    );
  }

  const { result: undelegateResult } = await planUndelegateAll(publicClient, account);
  const undelegatePlan = undelegateResult.plans[0];

  // Safety check: unstake must NOT be possible yet.
  await assertUnstakeReverts(
    publicClient,
    account,
    amount,
    `Unstake ${formatZrx(amount)} ZRX before epoch end`
  );

  const block = await publicClient.getBlock();
  const now = block.timestamp;
  const epochEndTime =
    epochInfo.currentEpochStartTimeInSeconds + epochInfo.epochDurationInSeconds;
  if (now <= epochEndTime + END_EPOCH_PADDING_SECONDS) {
    throw new Error(
      `Epoch ${epochInfo.currentEpoch.toString()} has not ended yet. ` +
        `Wait until ${new Date(
          Number(epochEndTime + END_EPOCH_PADDING_SECONDS) * 1000
        ).toISOString()} before running this command.`
    );
  }

  const endEpochPlan: OperationPlan = {
    to: STAKING_PROXY_ADDRESS,
    value: 0n,
    data: encodeEndEpoch(),
    description: `End staking epoch ${epochInfo.currentEpoch.toString()}`,
  };

  const atomicPlans: OperationPlan[] = [
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
  ].map((p) => ({ ...p, skipSimulation: true }));

  return {
    plans: [undelegatePlan, endEpochPlan, ...atomicPlans],
    summary: `Migrate ${formatZrx(
      amount
    )} ZRX from legacy stake to wZRX governance (delegate to ${delegatee})`,
  };
}
