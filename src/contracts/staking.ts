/**
 * Encoding helpers for the 0x Staking Proxy.
 *
 * All staking operations are delegate-called through the proxy at
 * STAKING_PROXY_ADDRESS. The ABI is defined in src/config/constants.ts.
 *
 * GitHub source: src/contracts/staking.ts
 */

import {
  decodeFunctionData,
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
import { multicallRead } from '../ethereum/multicall.js';
import { withRetry } from '../ethereum/retry.js';
import { splitByWeights, splitEqually } from '../utils/amounts.js';
import { fetchUndelegateAllCalldata } from './tupleFixer.js';

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

export function encodeEndEpoch(): Hex {
  return encodeFunctionData({
    abi: STAKING_PROXY_ABI,
    functionName: 'endEpoch',
    args: [],
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

export interface EpochInfo {
  currentEpoch: bigint;
  currentEpochStartTimeInSeconds: bigint;
  epochDurationInSeconds: bigint;
}

export async function readEpochInfo(publicClient: PublicClient): Promise<EpochInfo> {
  const [currentEpoch, currentEpochStartTimeInSeconds, epochDurationInSeconds] =
    await withRetry(() =>
      multicallRead(publicClient, [
        { address: STAKING_PROXY_ADDRESS, abi: STAKING_PROXY_ABI, functionName: 'currentEpoch' },
        { address: STAKING_PROXY_ADDRESS, abi: STAKING_PROXY_ABI, functionName: 'currentEpochStartTimeInSeconds' },
        { address: STAKING_PROXY_ADDRESS, abi: STAKING_PROXY_ABI, functionName: 'epochDurationInSeconds' },
      ])
    );
  return {
    currentEpoch: currentEpoch as bigint,
    currentEpochStartTimeInSeconds: currentEpochStartTimeInSeconds as bigint,
    epochDurationInSeconds: epochDurationInSeconds as bigint,
  };
}

export async function readOwnerUndelegatedStake(
  publicClient: PublicClient,
  staker: Address
): Promise<StoredBalance> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: STAKING_PROXY_ADDRESS,
      abi: STAKING_PROXY_ABI,
      functionName: 'getOwnerStakeByStatus',
      args: [staker, StakeStatus.UNDELEGATED],
    })
  )) as StoredBalance;
}

export async function readOwnerDelegatedStake(
  publicClient: PublicClient,
  staker: Address
): Promise<StoredBalance> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: STAKING_PROXY_ADDRESS,
      abi: STAKING_PROXY_ABI,
      functionName: 'getOwnerStakeByStatus',
      args: [staker, StakeStatus.DELEGATED],
    })
  )) as StoredBalance;
}

export async function readOwnerStakeStatuses(
  publicClient: PublicClient,
  staker: Address
): Promise<{ undelegated: StoredBalance; delegated: StoredBalance }> {
  const [undelegated, delegated] = await withRetry(() =>
    multicallRead(publicClient, [
      {
        address: STAKING_PROXY_ADDRESS,
        abi: STAKING_PROXY_ABI,
        functionName: 'getOwnerStakeByStatus',
        args: [staker, StakeStatus.UNDELEGATED],
      },
      {
        address: STAKING_PROXY_ADDRESS,
        abi: STAKING_PROXY_ABI,
        functionName: 'getOwnerStakeByStatus',
        args: [staker, StakeStatus.DELEGATED],
      },
    ])
  );
  return {
    undelegated: undelegated as StoredBalance,
    delegated: delegated as StoredBalance,
  };
}

export async function readStakeDelegatedToPool(
  publicClient: PublicClient,
  staker: Address,
  poolId: Hex
): Promise<StoredBalance> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: STAKING_PROXY_ADDRESS,
      abi: STAKING_PROXY_ABI,
      functionName: 'getStakeDelegatedToPoolByOwner',
      args: [staker, poolId],
    })
  )) as StoredBalance;
}

export interface DecodedMoveStake {
  from: StakeInfo;
  to: StakeInfo;
  amount: bigint;
}

export function decodeMoveStake(data: Hex): DecodedMoveStake {
  const decoded = decodeFunctionData({
    abi: STAKING_PROXY_ABI,
    data,
  });
  if (decoded.functionName !== 'moveStake') {
    throw new Error(`Expected moveStake calldata, got ${decoded.functionName}`);
  }
  const args = decoded.args as [
    { status: number; poolId: Hex },
    { status: number; poolId: Hex },
    bigint
  ];
  return {
    from: { status: args[0].status, poolId: args[0].poolId },
    to: { status: args[1].status, poolId: args[1].poolId },
    amount: args[2],
  };
}

export interface DelegatedPoolBalance {
  poolId: Hex;
  amount: bigint;
}

/**
 * Read the currently delegated pool balances for a staker by decoding the
 * TupleFixer undelegate-all calldata. This returns one entry per pool that has
 * a non-zero delegated balance in the *next* epoch.
 */
export async function fetchDelegatedPoolBalances(
  publicClient: PublicClient,
  staker: Address
): Promise<DelegatedPoolBalance[]> {
  const { encodedCalls } = await fetchUndelegateAllCalldata(publicClient, staker);
  const balances: DelegatedPoolBalance[] = [];
  for (const call of encodedCalls) {
    const decoded = decodeMoveStake(call);
    if (decoded.from.status !== StakeStatus.DELEGATED) continue;
    balances.push({ poolId: decoded.from.poolId, amount: decoded.amount });
  }
  return balances;
}

// --------------------------------------------------------------------------
// Rebalancing helpers
// --------------------------------------------------------------------------

export interface ScaledUndelegationResult {
  encodedCalls: Hex[];
  undelegatedAmounts: bigint[];
}

/**
 * Build moveStake calls that undelegate a specific `amount` proportionally from
 * the provided delegated pool balances. The returned parts always sum to
 * `amount` (any rounding remainder is assigned to the largest source).
 */
export function buildScaledUndelegation(
  sourceBalances: DelegatedPoolBalance[],
  amount: bigint
): ScaledUndelegationResult {
  if (amount < 0n) throw new Error('amount must be non-negative');
  const sourceTotal = sourceBalances.reduce((a, b) => a + b.amount, 0n);
  if (amount > sourceTotal) {
    throw new Error(
      `Cannot undelegate ${amount.toString()} from pools holding ${sourceTotal.toString()}`
    );
  }
  if (sourceBalances.length === 0 || amount === 0n) {
    return { encodedCalls: [], undelegatedAmounts: [] };
  }

  const weights = sourceBalances.map((b) => b.amount);
  const undelegatedAmounts = splitByWeights(amount, weights);
  const encodedCalls = sourceBalances.map((b, i) =>
    encodeUndelegateFromPool(b.poolId, undelegatedAmounts[i])
  );
  return { encodedCalls, undelegatedAmounts };
}

export interface RebalanceResult {
  encodedCalls: Hex[];
  sourceAmounts: bigint[];
  targetAmounts: bigint[];
}

/**
 * Build moveStake calls that move `amount` from a set of source delegated pools
 * to a set of target pools. The source side is scaled proportionally by current
 * balance; the target side is split equally. Any rounding remainders are
 * assigned to the last source/target respectively.
 */
export function buildRebalanceCalldata(
  sourceBalances: DelegatedPoolBalance[],
  targetPoolIds: Hex[],
  amount: bigint
): RebalanceResult {
  if (amount < 0n) throw new Error('amount must be non-negative');
  if (targetPoolIds.length === 0) throw new Error('targetPoolIds must not be empty');
  const sourceTotal = sourceBalances.reduce((a, b) => a + b.amount, 0n);
  if (amount > sourceTotal) {
    throw new Error(
      `Cannot rebalance ${amount.toString()} from pools holding ${sourceTotal.toString()}`
    );
  }
  if (sourceBalances.length === 0 || amount === 0n) {
    return { encodedCalls: [], sourceAmounts: [], targetAmounts: [] };
  }

  const sourceAmounts = splitByWeights(
    amount,
    sourceBalances.map((b) => b.amount)
  );
  const targetAmounts = splitEqually(amount, targetPoolIds.length);

  const encodedCalls: Hex[] = [
    ...sourceBalances.map((b, i) => encodeUndelegateFromPool(b.poolId, sourceAmounts[i])),
    ...targetPoolIds.map((poolId, i) => encodeDelegateToPool(poolId, targetAmounts[i])),
  ];

  return { encodedCalls, sourceAmounts, targetAmounts };
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
