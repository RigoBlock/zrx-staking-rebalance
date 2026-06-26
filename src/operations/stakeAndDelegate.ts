/**
 * Operation: atomically stake new ZRX and delegate equally.
 *
 * Uses StakingProxy.batchExecute to combine stake() + moveStake() calls.
 * Because the staking system pulls ZRX via the ERC20 Asset Proxy, the user
 * must first approve ERC20_PROXY_ADDRESS and then reset the allowance after
 * staking.
 *
 * GitHub source: src/operations/stakeAndDelegate.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import {
  ERC20_PROXY_ADDRESS,
  STAKING_PROXY_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  encodeApproveZrxToErc20Proxy,
  encodeResetZrxErc20ProxyApproval,
  readZrxBalanceAndAllowance,
} from '../contracts/zrx.js';
import {
  encodeBatchExecute,
  encodeEqualDelegation,
  encodeStake,
} from '../contracts/staking.js';
import { formatAllocations, formatZrx, splitEqually, validateSplit } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planStakeAndDelegate(
  publicClient: PublicClient,
  staker: Address,
  amount: bigint,
  poolIds: Hex[]
): Promise<OperationPlanResult> {
  if (poolIds.length === 0) {
    throw new Error('At least one target pool is required');
  }

  const { balance, allowance } = await readZrxBalanceAndAllowance(
    publicClient,
    staker,
    ERC20_PROXY_ADDRESS
  );
  if (balance < amount) {
    throw new Error(
      `Insufficient ZRX balance: have ${formatZrx(balance)}, need ${formatZrx(
        amount
      )}`
    );
  }

  const needsApproval = allowance < amount;

  const allocations = splitEqually(amount, poolIds.length);
  validateSplit(allocations, amount);

  const stakingCalls = [
    encodeStake(amount),
    ...encodeEqualDelegation(poolIds, allocations),
  ];

  const plans = [
    ...(needsApproval
      ? [
          {
            to: ZRX_TOKEN_ADDRESS,
            value: 0n,
            data: encodeApproveZrxToErc20Proxy(amount),
            description: `Approve ERC20 Asset Proxy to spend ${formatZrx(
              amount
            )} ZRX`,
          },
        ]
      : []),
    {
      to: STAKING_PROXY_ADDRESS,
      value: 0n,
      data: encodeBatchExecute(stakingCalls),
      description: `Stake ${formatZrx(amount)} ZRX and delegate equally:\n${formatAllocations(
        poolIds,
        allocations
      )}`,
    },
    {
      to: ZRX_TOKEN_ADDRESS,
      value: 0n,
      data: encodeResetZrxErc20ProxyApproval(),
      description: 'Reset ERC20 Asset Proxy ZRX approval to 0',
    },
  ];

  return {
    plans,
    summary: `Stake + delegate ${formatZrx(amount)} ZRX${
      needsApproval ? ' (with approval + reset)' : ''
    }`,
  };
}
