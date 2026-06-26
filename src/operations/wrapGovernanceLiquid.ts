/**
 * Operation: wrap liquid (already unstaked) ZRX into wZRX governance.
 *
 * This does NOT touch delegated or staked ZRX. For the full legacy-stake
 * migration flow, use `wrap-governance` instead.
 *
 * GitHub source: src/operations/wrapGovernanceLiquid.ts
 */

import type { Address, PublicClient } from 'viem';
import {
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  encodeApproveZrxToWzrx,
  encodeResetZrxApprovalForWzrx,
  readZrxBalance,
} from '../contracts/zrx.js';
import { encodeDelegateWzrx, encodeWrapZrxFor } from '../contracts/wzrx.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planWrapGovernanceLiquid(
  publicClient: PublicClient,
  account: Address,
  amount: bigint,
  delegatee: Address
): Promise<OperationPlanResult> {
  const balance = await readZrxBalance(publicClient, account);
  if (balance < amount) {
    throw new Error(
      `Insufficient liquid ZRX balance: have ${formatZrx(balance)}, need ${formatZrx(
        amount
      )}`
    );
  }

  return {
    plans: [
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
    summary: `Wrap ${formatZrx(amount)} ZRX to wZRX (delegate to ${delegatee})`,
  };
}
