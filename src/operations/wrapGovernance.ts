/**
 * Operation: wrap liquid ZRX into the wZRX governance token.
 *
 * SECURITY: This function does NOT unstake. To keep voting power in both the
 * legacy staking system and the new governance system, only liquid ZRX (e.g.
 * ZRX transferred from another wallet, or ZRX previously unstaked via the
 * separate `unstake` command) is wrapped.
 *
 * GitHub source: src/operations/wrapGovernance.ts
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

export async function planWrapGovernance(
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
