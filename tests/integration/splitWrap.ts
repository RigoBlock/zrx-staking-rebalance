/**
 * Test-only helper: plan a split wZRX governance deposit across multiple
 * recipient accounts, each delegating to the operator of one target pool.
 *
 * The staker must hold enough liquid ZRX and must approve the wZRX contract.
 *
 * GitHub source: tests/integration/splitWrap.ts
 */

import type { Address, Hex } from 'viem';
import {
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../../src/config/constants.js';
import { getPoolById } from '../../src/config/pools.js';
import { encodeApproveZrxToWzrx } from '../../src/contracts/zrx.js';
import {
  encodeDelegateWzrx,
  encodeWrapZrxFor,
} from '../../src/contracts/wzrx.js';
import { splitEqually } from '../../src/utils/amounts.js';
import type { OperationPlan } from '../../src/operations/types.js';

export interface SplitWrapGovernancePlan {
  stakerPlans: OperationPlan[];
  recipientPlans: OperationPlan[];
  shares: bigint[];
  delegatees: Address[];
}

export function planSplitWrapGovernance(
  _staker: Address,
  totalAmount: bigint,
  targetPoolIds: Hex[],
  recipients: Address[]
): SplitWrapGovernancePlan {
  if (targetPoolIds.length === 0) throw new Error('targetPoolIds must not be empty');
  if (targetPoolIds.length !== recipients.length) {
    throw new Error('targetPoolIds and recipients must have the same length');
  }

  const shares = splitEqually(totalAmount, targetPoolIds.length);
  const delegatees = targetPoolIds.map((poolId) => {
    const pool = getPoolById(poolId);
    if (!pool) throw new Error(`Unknown pool ${poolId}`);
    return pool.operator;
  });

  const stakerPlans: OperationPlan[] = [
    {
      to: ZRX_TOKEN_ADDRESS,
      value: 0n,
      data: encodeApproveZrxToWzrx(totalAmount),
      description: `Approve wZRX to spend ${totalAmount.toString()} ZRX`,
    },
    ...recipients.map((recipient, i) => ({
      to: WZRX_TOKEN_ADDRESS,
      value: 0n,
      data: encodeWrapZrxFor(recipient, shares[i]),
      description: `Wrap ${shares[i].toString()} ZRX into wZRX for recipient ${i + 1}`,
    })),
    {
      to: ZRX_TOKEN_ADDRESS,
      value: 0n,
      data: encodeApproveZrxToWzrx(0n),
      description: 'Reset ZRX approval to wZRX contract',
    },
  ];

  const recipientPlans: OperationPlan[] = delegatees.map((delegatee) => ({
    to: WZRX_TOKEN_ADDRESS,
    value: 0n,
    data: encodeDelegateWzrx(delegatee),
    description: `Delegate wZRX voting power to pool operator ${delegatee}`,
  }));

  return { stakerPlans, recipientPlans, shares, delegatees };
}
