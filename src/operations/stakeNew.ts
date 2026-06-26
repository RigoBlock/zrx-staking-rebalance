/**
 * Operation: stake new ZRX tokens.
 *
 * The 0x staking system pulls ZRX via the ERC20 Asset Proxy, so the user must
 * approve ERC20_PROXY_ADDRESS before staking. The approval is reset to 0
 * immediately after the stake.
 *
 * GitHub source: src/operations/stakeNew.ts
 */

import type { Address, PublicClient } from 'viem';
import {
  ERC20_PROXY_ADDRESS,
  STAKING_PROXY_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import {
  encodeApproveZrxToErc20Proxy,
  encodeResetZrxErc20ProxyApproval,
  readZrxAllowance,
  readZrxBalance,
} from '../contracts/zrx.js';
import { encodeStake } from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlanResult } from './types.js';

export async function planStakeNew(
  publicClient: PublicClient,
  staker: Address,
  amount: bigint
): Promise<OperationPlanResult> {
  const balance = await readZrxBalance(publicClient, staker);
  if (balance < amount) {
    throw new Error(
      `Insufficient ZRX balance: have ${formatZrx(balance)}, need ${formatZrx(
        amount
      )}`
    );
  }

  const allowance = await readZrxAllowance(
    publicClient,
    staker,
    ERC20_PROXY_ADDRESS
  );
  const needsApproval = allowance < amount;

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
      data: encodeStake(amount),
      description: `Stake ${formatZrx(amount)} ZRX into the 0x staking contract`,
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
    summary: `Stake ${formatZrx(amount)} ZRX${
      needsApproval ? ' (with approval + reset)' : ''
    }`,
  };
}
