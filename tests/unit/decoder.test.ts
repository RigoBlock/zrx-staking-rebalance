import { describe, expect, it } from 'vitest';
import { decodeSafeTransactionData } from '../../src/safe/decoder.js';
import {
  encodeBatchExecute,
  encodeStake,
  encodeUnstake,
} from '../../src/contracts/staking.js';
import { STAKING_PROXY_ADDRESS, ZRX_TOKEN_ADDRESS } from '../../src/config/constants.js';
import { encodeApproveZrxToErc20Proxy } from '../../src/contracts/zrx.js';

describe('Safe transaction decoder', () => {
  it('decodes a batchExecute of staking calls', () => {
    const data = encodeBatchExecute([encodeStake(10n ** 18n), encodeUnstake(5n * 10n ** 17n)]);
    const decoded = decodeSafeTransactionData(data, STAKING_PROXY_ADDRESS);
    expect(decoded).toBeDefined();
    expect(decoded).toHaveLength(2);
    expect(decoded?.[0]).toContain('Stake');
    expect(decoded?.[1]).toContain('Unstake');
  });

  it('decodes an ERC20 approve', () => {
    const data = encodeApproveZrxToErc20Proxy(10n ** 18n);
    const decoded = decodeSafeTransactionData(data, ZRX_TOKEN_ADDRESS);
    expect(decoded?.[0]).toContain('Approve');
  });

  it('returns undefined for unknown targets', () => {
    const decoded = decodeSafeTransactionData('0x', '0x0000000000000000000000000000000000000001');
    expect(decoded).toBeUndefined();
  });
});
