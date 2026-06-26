/**
 * Encoding helpers for the 0x Staking Proxy.
 *
 * All staking operations are delegate-called through the proxy at
 * STAKING_PROXY_ADDRESS. The ABI is defined in src/config/constants.ts.
 *
 * GitHub source: src/contracts/staking.ts
 */

import {
  encodeFunctionData,
  type Address,
  type Hex,
  type PublicClient,
} from 'viem';
import {
  STAKING_PROXY_ABI,
  STAKING_PROXY_ADDRESS,
} from '../config/constants.js';
import { getPoolLabel } from '../config/pools.js';
import { StakeStatus, type StakeInfo } from '../types.js';

// --------------------------------------------------------------------------
// Calldata encoders
// --------------------------------------------------------------------------

export function encodeStake(amount: bigint): Hex {
  return encodeFunctionData({
    abi: STAKING_PROXY_ABI,
    functionName: 'stake',
    args: [amount],
  });
}

export function encodeUnstake(amount: bigint): Hex {
  return encodeFunctionData({
    abi: STAKING_PROXY_ABI,
    functionName: 'unstake',
    args: [amount],
  });
}

export function encodeMoveStake(
  from: StakeInfo,
  to: StakeInfo,
  amount: bigint
): Hex {
  return encodeFunctionData({
    abi: STAKING_PROXY_ABI,
    functionName: 'moveStake',
    args: [
      { status: from.status, poolId: from.poolId },
      { status: to.status, poolId: to.poolId },
      amount,
    ],
  });
}

export function encodeBatchExecute(calls: Hex[]): Hex {
  return encodeFunctionData({
    abi: STAKING_PROXY_ABI,
    functionName: 'batchExecute',
    args: [calls],
  });
}

// --------------------------------------------------------------------------
// High-level delegation helpers
// --------------------------------------------------------------------------

export function encodeDelegateToPool(poolId: Hex, amount: bigint): Hex {
  return encodeMoveStake(
    { status: StakeStatus.UNDELEGATED, poolId: `0x${'0'.repeat(64)}` as Hex },
    { status: StakeStatus.DELEGATED, poolId },
    amount
  );
}

export function encodeUndelegateFromPool(poolId: Hex, amount: bigint): Hex {
  return encodeMoveStake(
    { status: StakeStatus.DELEGATED, poolId },
    { status: StakeStatus.UNDELEGATED, poolId: `0x${'0'.repeat(64)}` as Hex },
    amount
  );
}

/** Encode equal delegation across an array of pools. */
export function encodeEqualDelegation(
  poolIds: Hex[],
  amounts: bigint[]
): Hex[] {
  if (poolIds.length !== amounts.length) {
    throw new Error('poolIds and amounts must have the same length');
  }
  return poolIds.map((poolId, i) => encodeDelegateToPool(poolId, amounts[i]));
}

// --------------------------------------------------------------------------
// On-chain reads
// --------------------------------------------------------------------------

export interface StoredBalance {
  currentEpoch: bigint;
  currentEpochBalance: bigint;
  nextEpochBalance: bigint;
}

export async function readOwnerUndelegatedStake(
  publicClient: PublicClient,
  staker: Address
): Promise<StoredBalance> {
  const result = (await publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: STAKING_PROXY_ABI,
    functionName: 'getOwnerStakeByStatus',
    args: [staker, StakeStatus.UNDELEGATED],
  })) as { currentEpoch: bigint; currentEpochBalance: bigint; nextEpochBalance: bigint };
  return result;
}

export async function readStakeDelegatedToPool(
  publicClient: PublicClient,
  staker: Address,
  poolId: Hex
): Promise<StoredBalance> {
  const result = (await publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: STAKING_PROXY_ABI,
    functionName: 'getStakeDelegatedToPoolByOwner',
    args: [staker, poolId],
  })) as { currentEpoch: bigint; currentEpochBalance: bigint; nextEpochBalance: bigint };
  return result;
}

// --------------------------------------------------------------------------
// Human-readable descriptions
// --------------------------------------------------------------------------

export function describeMoveStake(
  from: StakeInfo,
  to: StakeInfo,
  amount: bigint
): string {
  const fromLabel =
    from.status === StakeStatus.DELEGATED
      ? getPoolLabel(from.poolId)
      : 'undelegated';
  const toLabel =
    to.status === StakeStatus.DELEGATED
      ? getPoolLabel(to.poolId)
      : 'undelegated';
  return `Move ${amount.toString()} ZRX stake from ${fromLabel} to ${toLabel}`;
}
