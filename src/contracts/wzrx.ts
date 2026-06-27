/**
 * Wrapped ZRX (wZRX) governance helpers.
 *
 * wZRX is an OpenZeppelin ERC20Wrapper that mints 1:1 for ZRX. The flow to
 * enter governance is:
 *   1. approve ZRX to the wZRX contract
 *   2. depositFor(account, amount)
 *   3. delegate(delegatee) — assigns voting power
 *   4. reset ZRX approval
 *
 * GitHub source: src/contracts/wzrx.ts
 */

import { encodeFunctionData, type Address, type Hex, type PublicClient } from 'viem';
import { WZRX_ABI, WZRX_TOKEN_ADDRESS } from '../config/constants.js';
import { withRetry } from '../ethereum/retry.js';
import { encodeApprove } from './zrx.js';

export function encodeWrapZrxFor(account: Address, amount: bigint): Hex {
  return encodeFunctionData({
    abi: WZRX_ABI,
    functionName: 'depositFor',
    args: [account, amount],
  });
}

export function encodeDelegateWzrx(delegatee: Address): Hex {
  return encodeFunctionData({
    abi: WZRX_ABI,
    functionName: 'delegate',
    args: [delegatee],
  });
}

/** Encode a ZRX approval to the wZRX spender. */
export function encodeApproveZrxToWzrx(amount: bigint): Hex {
  return encodeApprove(WZRX_TOKEN_ADDRESS, amount);
}

/** Encode a ZRX approval reset for the wZRX spender. */
export function encodeResetZrxApprovalForWzrx(): Hex {
  return encodeApprove(WZRX_TOKEN_ADDRESS, 0n);
}

export async function readWzrxBalance(
  publicClient: PublicClient,
  account: Address
): Promise<bigint> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: WZRX_TOKEN_ADDRESS,
      abi: WZRX_ABI,
      functionName: 'balanceOf',
      args: [account],
    })
  )) as bigint;
}

export async function readWzrxDelegatee(
  publicClient: PublicClient,
  account: Address
): Promise<Address> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: WZRX_TOKEN_ADDRESS,
      abi: WZRX_ABI,
      functionName: 'delegates',
      args: [account],
    })
  )) as Address;
}
