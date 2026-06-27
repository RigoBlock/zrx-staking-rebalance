/**
 * Operation: undelegate a specific amount from non-target pools, wait for the
 * epoch to end, then atomically unstake + approve + wrap + delegate.
 *
 * This is intended for treasury migrations where certain pools must be
 * preserved while the remainder is converted into wZRX governance tokens.
 *
 * GitHub source: src/operations/wrapGovernanceExcludePools.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import {
  STAKING_PROXY_ADDRESS,
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  buildScaledUndelegation,
  encodeBatchExecute,
  encodeEndEpoch,
  encodeUnstake,
  fetchDelegatedPoolBalances,
  type DelegatedPoolBalance,
} from '../contracts/staking.js';
import {
  encodeApproveZrxToWzrx,
  encodeResetZrxApprovalForWzrx,
} from '../contracts/zrx.js';
import {
  encodeDelegateWzrx,
  encodeWrapZrxFor,
} from '../contracts/wzrx.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planWrapGovernanceExcludePools(
  publicClient: PublicClient,
  staker: Address,
  amount: bigint,
  excludePoolIds: Hex[],
  recipient: Address
): Promise<OperationPlanResult> {
  if (amount <= 0n) throw new Error('amount must be positive');

  const excludeSet = new Set(excludePoolIds.map((id) => id.toLowerCase()));
  const allBalances = await fetchDelegatedPoolBalances(publicClient, staker);
  const sourceBalances: DelegatedPoolBalance[] = allBalances.filter(
    (b) => !excludeSet.has(b.poolId.toLowerCase())
  );

  const sourceTotal = sourceBalances.reduce((a, b) => a + b.amount, 0n);
  if (amount > sourceTotal) {
    throw new Error(
      `Cannot undelegate ${formatZrx(amount)} from non-target pools: only ${formatZrx(
        sourceTotal
      )} available`
    );
  }

  const { encodedCalls: undelegateCalls } = buildScaledUndelegation(
    sourceBalances,
    amount
  );

  const wrapAmount = amount;
  const summary = `Undelegate ${formatZrx(amount)} ZRX from non-target pools, end epoch, and wrap to wZRX for ${recipient}`;

  return {
    plans: [
      {
        to: STAKING_PROXY_ADDRESS,
        value: 0n,
        data: encodeBatchExecute(undelegateCalls),
        description: `Undelegate ${formatZrx(amount)} ZRX from non-target pools`,
      },
      {
        to: STAKING_PROXY_ADDRESS,
        value: 0n,
        data: encodeEndEpoch(),
        description: 'Advance to the next epoch to unlock undelegated stake',
      },
      {
        to: STAKING_PROXY_ADDRESS,
        value: 0n,
        data: encodeUnstake(wrapAmount),
        description: `Unstake ${formatZrx(wrapAmount)} ZRX`,
      },
      {
        to: ZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeApproveZrxToWzrx(wrapAmount),
        description: `Approve wZRX to spend ${formatZrx(wrapAmount)} ZRX`,
      },
      {
        to: WZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeWrapZrxFor(recipient, wrapAmount),
        description: `Wrap ${formatZrx(wrapAmount)} ZRX into wZRX for ${recipient}`,
      },
      {
        to: WZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeDelegateWzrx(recipient),
        description: `Delegate wZRX voting power to ${recipient}`,
      },
      {
        to: ZRX_TOKEN_ADDRESS,
        value: 0n,
        data: encodeResetZrxApprovalForWzrx(),
        description: 'Reset ZRX approval to wZRX contract',
      },
    ],
    summary,
  };
}
