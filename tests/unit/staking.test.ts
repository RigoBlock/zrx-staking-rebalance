import { describe, expect, it } from 'vitest';
import {
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
});
