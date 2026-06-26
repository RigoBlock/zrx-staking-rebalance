/**
 * TupleFixer helper to retrieve undelegate-all calldata.
 *
 * Real mainnet address: 0x609abe9b2b09d1e2c2abfe93dfffd9f596d9a06e
 * A local fallback scanner is kept for testing / resilience.
 *
 * GitHub source: src/contracts/tupleFixer.ts
 */

import {
  encodeFunctionData,
  type Address,
  type Hex,
  type PublicClient,
} from 'viem';
import { TUPLE_FIXER_ABI } from '../config/constants.js';
import type { UndelegateAllCalldata } from '../types.js';
import { readStakeDelegatedToPool } from './staking.js';
import { StakeStatus, type StakeInfo } from '../types.js';
import { encodeMoveStake } from './staking.js';

/** Rigoblock TupleFixer contract address on Ethereum mainnet. */
export const TUPLE_FIXER_ADDRESS: Address =
  '0x609abe9b2b09d1e2c2abfe93dfffd9f596d9a06e';

/** Kept for backward compatibility; the address is now real. */
export const TUPLE_FIXER_MOCK_ADDRESS = TUPLE_FIXER_ADDRESS;
export const IS_TUPLE_FIXER_MOCK = false;

const LAST_POOL_ID = 256; // Upper bound used by the helper to avoid DoS.

/**
 * Fetch undelegate-all calldata.
 *
 * If the mock flag is set, this performs a local scan of pool ids 1..256 and
 * encodes a moveStake(Delegated -> Undelegated) for every pool where the
 * staker has a non-zero next-epoch balance. This matches the described
 * TupleFixer behavior but is implemented client-side.
 */
export async function fetchUndelegateAllCalldata(
  publicClient: PublicClient,
  staker: Address
): Promise<UndelegateAllCalldata> {
  if (!IS_TUPLE_FIXER_MOCK) {
    const result = (await publicClient.readContract({
      address: TUPLE_FIXER_ADDRESS,
      abi: TUPLE_FIXER_ABI,
      functionName: 'encodeUndelegateAll',
      args: [],
      account: staker,
    })) as [bigint, Hex[]];
    return {
      totalUndelegatedAmount: result[0],
      encodedCalls: result[1],
    };
  }

  // Fallback mock implementation.
  const encodedCalls: Hex[] = [];
  let totalUndelegatedAmount = 0n;

  for (let i = 1; i <= LAST_POOL_ID; i++) {
    const poolId = `0x${i.toString(16).padStart(64, '0')}` as Hex;
    try {
      const balance = await readStakeDelegatedToPool(publicClient, staker, poolId);
      if (balance.nextEpochBalance > 0n) {
        const from: StakeInfo = {
          status: StakeStatus.DELEGATED,
          poolId,
        };
        const to: StakeInfo = {
          status: StakeStatus.UNDELEGATED,
          poolId: `0x${'0'.repeat(64)}` as Hex,
        };
        encodedCalls.push(encodeMoveStake(from, to, balance.nextEpochBalance));
        totalUndelegatedAmount += balance.nextEpochBalance;
      }
    } catch {
      // Pool may not exist; continue scanning.
    }
  }

  return { totalUndelegatedAmount, encodedCalls };
}

/** Encode the view call itself (useful for dry-run previews). */
export function encodeUndelegateAllView(): Hex {
  return encodeFunctionData({
    abi: TUPLE_FIXER_ABI,
    functionName: 'encodeUndelegateAll',
    args: [],
  });
}
