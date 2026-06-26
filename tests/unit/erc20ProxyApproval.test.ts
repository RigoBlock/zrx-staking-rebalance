import { describe, expect, it, vi } from 'vitest';
import { createPublicClient, http } from 'viem';
import { mainnet } from 'viem/chains';
import { planStakeNew } from '../../src/operations/stakeNew.js';
import { planStakeAndDelegate } from '../../src/operations/stakeAndDelegate.js';
import * as zrx from '../../src/contracts/zrx.js';
import { ZRX_TOKEN_ADDRESS } from '../../src/config/constants.js';

const publicClient = createPublicClient({
  chain: mainnet,
  transport: http('http://127.0.0.1:1'),
});

const staker = '0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B' as `0x${string}`;
const poolId = '0x0000000000000000000000000000000000000000000000000000000000000031' as `0x${string}`;

describe('ERC20 Asset Proxy approval', () => {
  it('stake-new includes approval and reset to the ERC20 Asset Proxy', async () => {
    vi.spyOn(zrx, 'readZrxBalanceAndAllowance').mockResolvedValue({
      balance: 1000n,
      allowance: 0n,
    });

    const { plans } = await planStakeNew(publicClient, staker, 100n);

    const approval = plans.find(
      (p) => p.to.toLowerCase() === ZRX_TOKEN_ADDRESS.toLowerCase() &&
        p.description.toLowerCase().includes('approve') &&
        p.description.toLowerCase().includes('erc20 asset proxy')
    );
    const reset = plans.find(
      (p) => p.to.toLowerCase() === ZRX_TOKEN_ADDRESS.toLowerCase() &&
        p.description.toLowerCase().includes('reset') &&
        p.description.toLowerCase().includes('erc20 asset proxy')
    );

    expect(approval).toBeDefined();
    expect(reset).toBeDefined();
  });

  it('stake-and-delegate includes approval and reset to the ERC20 Asset Proxy', async () => {
    vi.spyOn(zrx, 'readZrxBalanceAndAllowance').mockResolvedValue({
      balance: 1000n,
      allowance: 0n,
    });

    const { plans } = await planStakeAndDelegate(publicClient, staker, 100n, [poolId]);

    const approval = plans.find(
      (p) => p.to.toLowerCase() === ZRX_TOKEN_ADDRESS.toLowerCase() &&
        p.description.toLowerCase().includes('approve') &&
        p.description.toLowerCase().includes('erc20 asset proxy')
    );
    const reset = plans.find(
      (p) => p.to.toLowerCase() === ZRX_TOKEN_ADDRESS.toLowerCase() &&
        p.description.toLowerCase().includes('reset') &&
        p.description.toLowerCase().includes('erc20 asset proxy')
    );

    expect(approval).toBeDefined();
    expect(reset).toBeDefined();
  });
});
