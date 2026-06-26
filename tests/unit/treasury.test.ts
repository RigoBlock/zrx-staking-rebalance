import { describe, expect, it } from 'vitest';
import { decodeFunctionData, parseEther } from 'viem';
import {
  buildTreasuryMigrationActions,
  encodeTreasuryExecute,
  encodeTreasuryPropose,
  ZRX_TREASURY_ABI,
} from '../../src/contracts/treasury.js';
import {
  MATIC_TOKEN_ADDRESS,
  POLYGON_MIGRATION_ADDRESS,
  POL_TOKEN_ADDRESS,
  WCELO_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../../src/config/constants.js';

describe('treasury migration', () => {
  it('builds actions for ZRX, wCELO and MATIC->POL', () => {
    const balances = {
      zrx: parseEther('100'),
      wCelo: parseEther('200'),
      matic: parseEther('300'),
    };
    const actions = buildTreasuryMigrationActions(balances);

    expect(actions).toHaveLength(5);

    expect(actions[0].target).toBe(ZRX_TOKEN_ADDRESS);
    expect(actions[1].target).toBe(WCELO_TOKEN_ADDRESS);

    const maticActions = actions.slice(2);
    expect(maticActions[0].target).toBe(MATIC_TOKEN_ADDRESS);
    expect(maticActions[1].target).toBe(POLYGON_MIGRATION_ADDRESS);
    expect(maticActions[2].target).toBe(POL_TOKEN_ADDRESS);
  });

  it('skips zero balances', () => {
    const actions = buildTreasuryMigrationActions({
      zrx: parseEther('50'),
      wCelo: 0n,
      matic: 0n,
    });
    expect(actions).toHaveLength(1);
    expect(actions[0].target).toBe(ZRX_TOKEN_ADDRESS);
  });

  it('encodes a propose call', () => {
    const actions = buildTreasuryMigrationActions({
      zrx: parseEther('10'),
      wCelo: 0n,
      matic: 0n,
    });
    const data = encodeTreasuryPropose(
      actions,
      123n,
      'test proposal',
      []
    );
    const decoded = decodeFunctionData({ abi: ZRX_TREASURY_ABI, data });
    expect(decoded.functionName).toBe('propose');
    expect(decoded.args?.[1]).toBe(123n);
  });

  it('encodes an execute call', () => {
    const actions = buildTreasuryMigrationActions({
      zrx: parseEther('10'),
      wCelo: 0n,
      matic: 0n,
    });
    const data = encodeTreasuryExecute(7n, actions);
    const decoded = decodeFunctionData({ abi: ZRX_TREASURY_ABI, data });
    expect(decoded.functionName).toBe('execute');
    expect(decoded.args?.[0]).toBe(7n);
  });
});
