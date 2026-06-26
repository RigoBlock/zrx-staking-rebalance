/**
 * Target staking pool definitions and helper functions.
 *
 * GitHub source: src/config/pools.ts
 */

import type { Address, Hex } from 'viem';
import type { StakingPool } from '../types.js';
import {
  TARGET_POOL_31,
  TARGET_POOL_34,
  TARGET_POOL_48,
} from './constants.js';

/** Canonical target pools supplied by the user. */
export const KNOWN_TARGET_POOLS: StakingPool[] = [
  {
    poolId: TARGET_POOL_31,
    operator: '0x4990cE223209FCEc4ec4c1ff6E0E81eebD8Cca08',
    name: 'Target Pool 0x31',
  },
  {
    poolId: TARGET_POOL_48,
    operator: '0x1ce0e8757a1dD7502a4ECF0D211BDD27214F7244',
    name: 'Target Pool 0x48',
  },
  {
    poolId: TARGET_POOL_34,
    operator: '0xcA9F5049c1Ea8FC78574f94B7Cf5bE5fEE354C31',
    name: 'Target Pool 0x34',
  },
];

const POOL_BY_ID = new Map<Hex, StakingPool>(
  KNOWN_TARGET_POOLS.map((p) => [p.poolId.toLowerCase() as Hex, p])
);

const POOL_BY_OPERATOR = new Map<Address, StakingPool>(
  KNOWN_TARGET_POOLS.map((p) => [p.operator.toLowerCase() as Address, p])
);

/** Resolve a pool by its id (case-insensitive). */
export function getPoolById(poolId: Hex): StakingPool | undefined {
  return POOL_BY_ID.get(poolId.toLowerCase() as Hex);
}

/** Resolve a pool by its operator address (case-insensitive). */
export function getPoolByOperator(operator: Address): StakingPool | undefined {
  return POOL_BY_OPERATOR.get(operator.toLowerCase() as Address);
}

/** Human-readable label for a pool id. */
export function getPoolLabel(poolId: Hex): string {
  return getPoolById(poolId)?.name ?? poolId;
}

/**
 * Build the final list of target pool ids.
 * If none are provided, returns the 3 known pools.
 * If a single extra pool id is passed, it is appended (useful for the
 * eventual 4th delegate).
 */
export function resolveTargetPools(extras?: Hex[]): Hex[] {
  const pools = KNOWN_TARGET_POOLS.map((p) => p.poolId);
  if (extras && extras.length > 0) {
    pools.push(...extras);
  }
  return pools;
}

/** Validate that every pool id is a 32-byte hex string. */
export function validatePoolIds(poolIds: Hex[]): Hex[] {
  for (const id of poolIds) {
    if (!id.startsWith('0x') || id.length !== 66) {
      throw new Error(`Invalid pool id (must be bytes32): ${id}`);
    }
  }
  return poolIds;
}
