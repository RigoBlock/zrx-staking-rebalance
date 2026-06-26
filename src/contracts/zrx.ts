/**
 * ZRX ERC20 helpers.
 *
 * IMPORTANT: the 0x staking system does NOT pull ZRX from the staker via the
 * StakingProxy. Instead, the ZRX Vault calls the ERC20 Asset Proxy
 * (ERC20_PROXY_ADDRESS) with encoded asset data. Therefore the staker must
 * approve ERC20_PROXY_ADDRESS before staking, and can reset that approval
 * afterward.
 *
 * For the wZRX governance wrapper, the spender is the wZRX contract itself.
 *
 * GitHub source: src/contracts/zrx.ts
 */

import {
  encodeFunctionData,
  type Address,
  type Hex,
  type PublicClient,
} from 'viem';
import {
  ERC20_ABI,
  ERC20_PROXY_ADDRESS,
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import { multicallRead } from '../ethereum/multicall.js';
import { withRetry } from '../ethereum/retry.js';

export function encodeApprove(spender: Address, amount: bigint): Hex {
  return encodeFunctionData({
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [spender, amount],
  });
}

export async function readZrxAllowance(
  publicClient: PublicClient,
  owner: Address,
  spender: Address
): Promise<bigint> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: ZRX_TOKEN_ADDRESS,
      abi: ERC20_ABI,
      functionName: 'allowance',
      args: [owner, spender],
    })
  )) as bigint;
}

export async function readZrxBalance(
  publicClient: PublicClient,
  account: Address
): Promise<bigint> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: ZRX_TOKEN_ADDRESS,
      abi: ERC20_ABI,
      functionName: 'balanceOf',
      args: [account],
    })
  )) as bigint;
}

export async function readZrxBalanceAndAllowance(
  publicClient: PublicClient,
  account: Address,
  spender: Address
): Promise<{ balance: bigint; allowance: bigint }> {
  const [balance, allowance] = await withRetry(() =>
    multicallRead(publicClient, [
      { address: ZRX_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] },
      { address: ZRX_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'allowance', args: [account, spender] },
    ])
  );
  return { balance: balance as bigint, allowance: allowance as bigint };
}

/** Approve the 0x ERC20 Asset Proxy so the ZRX Vault can pull ZRX on stake. */
export function encodeApproveZrxToErc20Proxy(amount: bigint): Hex {
  return encodeApprove(ERC20_PROXY_ADDRESS, amount);
}

/** Reset ERC20 Asset Proxy approval to 0. */
export function encodeResetZrxErc20ProxyApproval(): Hex {
  return encodeApprove(ERC20_PROXY_ADDRESS, 0n);
}

/** Approve ZRX to the wZRX wrapper contract. */
export function encodeApproveZrxToWzrx(amount: bigint): Hex {
  return encodeApprove(WZRX_TOKEN_ADDRESS, amount);
}

/** Reset ZRX approval to the wZRX wrapper contract. */
export function encodeResetZrxApprovalForWzrx(): Hex {
  return encodeApprove(WZRX_TOKEN_ADDRESS, 0n);
}
