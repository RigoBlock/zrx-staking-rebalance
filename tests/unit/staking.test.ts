import { describe, expect, it } from 'vitest';
import {
  buildRebalanceCalldata,
  buildScaledUndelegation,
  decodeMoveStake,
  encodeBatchExecute,
  encodeDelegateToPool,
  encodeEndEpoch,
  encodeEqualDelegation,
  encodeMoveStake,
  encodeStake,
  encodeUnstake,
} from '../../src/contracts/staking.js';
import { StakeStatus } from '../../src/types.js';
import { decodeFunctionData } from 'viem';
import { STAKING_PROXY_ABI } from '../../src/config/constants.js';

describe('staking calldata', () => {
  const poolId =
    '0x0000000000000000000000000000000000000000000000000000000000000031' as `0x${string}`;

  it('encodes stake', () => {
    const data = encodeStake(1000n);
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('stake');
    expect(decoded.args?.[0]).toBe(1000n);
  });

  it('encodes unstake', () => {
    const data = encodeUnstake(2000n);
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('unstake');
    expect(decoded.args?.[0]).toBe(2000n);
  });

  it('encodes moveStake', () => {
    const data = encodeMoveStake(
      { status: StakeStatus.UNDELEGATED, poolId: `0x${'0'.repeat(64)}` as `0x${string}` },
      { status: StakeStatus.DELEGATED, poolId },
      3000n
    );
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('moveStake');
    expect(decoded.args?.[2]).toBe(3000n);
  });

  it('encodes delegate to pool', () => {
    const data = encodeDelegateToPool(poolId, 4000n);
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('moveStake');
  });

  it('encodes equal delegation', () => {
    const calls = encodeEqualDelegation([poolId, poolId], [100n, 100n]);
    expect(calls).toHaveLength(2);
    calls.forEach((call) => {
      const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data: call });
      expect(decoded.functionName).toBe('moveStake');
    });
  });

  it('encodes batchExecute', () => {
    const calls = [encodeStake(100n), encodeUnstake(50n)];
    const data = encodeBatchExecute(calls);
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('batchExecute');
    expect(decoded.args?.[0]).toEqual(calls);
  });

  it('encodes endEpoch', () => {
    const data = encodeEndEpoch();
    const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
    expect(decoded.functionName).toBe('endEpoch');
  });

  it('decodes moveStake calldata', () => {
    const data = encodeMoveStake(
      { status: StakeStatus.DELEGATED, poolId },
      { status: StakeStatus.UNDELEGATED, poolId: `0x${'0'.repeat(64)}` as `0x${string}` },
      5000n
    );
    const decoded = decodeMoveStake(data);
    expect(decoded.from.status).toBe(StakeStatus.DELEGATED);
    expect(decoded.to.status).toBe(StakeStatus.UNDELEGATED);
    expect(decoded.amount).toBe(5000n);
  });

  it('rejects decoding non-moveStake calldata', () => {
    expect(() => decodeMoveStake(encodeStake(100n))).toThrow(
      'Expected moveStake calldata'
    );
  });

  describe('buildScaledUndelegation', () => {
    it('scales undelegation proportionally across pools', () => {
      const result = buildScaledUndelegation(
        [
          { poolId, amount: 75n },
          { poolId: `0x${'0'.repeat(63)}1` as `0x${string}`, amount: 25n },
        ],
        100n
      );
      expect(result.encodedCalls).toHaveLength(2);
      expect(result.undelegatedAmounts).toEqual([75n, 25n]);
    });

    it('throws when amount exceeds source total', () => {
      expect(() =>
        buildScaledUndelegation([{ poolId, amount: 100n }], 200n)
      ).toThrow('Cannot undelegate');
    });

    it('returns empty for zero amount', () => {
      const result = buildScaledUndelegation([{ poolId, amount: 100n }], 0n);
      expect(result.encodedCalls).toHaveLength(0);
    });
  });

  describe('buildRebalanceCalldata', () => {
    it('builds undelegate + delegate calls for a full rebalance', () => {
      const targetPool = `0x${'0'.repeat(63)}1` as `0x${string}`;
      const result = buildRebalanceCalldata(
        [{ poolId, amount: 100n }],
        [targetPool],
        100n
      );
      expect(result.encodedCalls).toHaveLength(2);
      expect(result.sourceAmounts).toEqual([100n]);
      expect(result.targetAmounts).toEqual([100n]);

      const first = decodeMoveStake(result.encodedCalls[0]);
      expect(first.from.status).toBe(StakeStatus.DELEGATED);
      expect(first.to.status).toBe(StakeStatus.UNDELEGATED);

      const second = decodeMoveStake(result.encodedCalls[1]);
      expect(second.from.status).toBe(StakeStatus.UNDELEGATED);
      expect(second.to.status).toBe(StakeStatus.DELEGATED);
      expect(second.to.poolId).toBe(targetPool);
    });

    it('throws when rebalance amount exceeds source total', () => {
      expect(() =>
        buildRebalanceCalldata([{ poolId, amount: 100n }], [poolId], 200n)
      ).toThrow('Cannot rebalance');
    });
  });
});
