import { describe, expect, it } from 'vitest';
import {
  getPoolById,
  getPoolByOperator,
  getPoolLabel,
  resolveTargetPools,
  validatePoolIds,
} from '../../src/config/pools.js';
import {
  TARGET_POOL_31,
  TARGET_POOL_34,
  TARGET_POOL_48,
} from '../../src/config/constants.js';

describe('pools', () => {
  it('resolves known pools by id', () => {
    const pool = getPoolById(TARGET_POOL_31);
    expect(pool).toBeDefined();
    expect(pool?.operator).toBe('0x4990cE223209FCEc4ec4c1ff6E0E81eebD8Cca08');
  });

  it('resolves known pools by operator', () => {
    const pool = getPoolByOperator('0x1ce0e8757a1dD7502a4ECF0D211BDD27214F7244');
    expect(pool?.poolId).toBe(TARGET_POOL_48);
  });

  it('returns hex id for unknown pools', () => {
    expect(getPoolLabel('0x0000000000000000000000000000000000000000000000000000000000000099')).toBe(
      '0x0000000000000000000000000000000000000000000000000000000000000099'
    );
  });

  it('returns default target pools', () => {
    expect(resolveTargetPools()).toEqual([
      TARGET_POOL_31,
      TARGET_POOL_48,
      TARGET_POOL_34,
    ]);
  });

  it('appends extra pools', () => {
    const extra = '0x0000000000000000000000000000000000000000000000000000000000000099';
    expect(resolveTargetPools([extra])).toEqual([
      TARGET_POOL_31,
      TARGET_POOL_48,
      TARGET_POOL_34,
      extra,
    ]);
  });

  it('validates bytes32 pool ids', () => {
    expect(() =>
      validatePoolIds(['0x1234'])
    ).toThrow('Invalid pool id');
  });
});
