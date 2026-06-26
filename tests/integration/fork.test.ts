/**
 * Integration tests against a mainnet fork.
 *
 * Run with `yarn test:foundry` (loads `.env` automatically). They start a local
 * anvil mainnet fork, seed a test account with ZRX stake, and exercise the
 * full rebalance / migration flows end-to-end.
 *
 * GitHub source: tests/integration/fork.test.ts
 */

import { describe, expect, it, beforeAll, beforeEach, afterAll } from 'vitest';
import { parseEther } from 'viem';
import { mainnet } from 'viem/chains';
import { startAnvilFork, type ForkInstance } from './anvil.js';
import {
  createTestWalletClient,
  endEpochOnFork,
  seedTestStake,
  setZrxBalance,
  TEST_EOA_ADDRESS,
} from './fixtures.js';
import { planUndelegateAll } from '../../src/operations/undelegateAll.js';
import { planStakeAndDelegate } from '../../src/operations/stakeAndDelegate.js';
import { planUndelegateAndDelegate } from '../../src/operations/undelegateAndDelegate.js';
import { planUnstake } from '../../src/operations/unstake.js';
import { planWrapGovernance } from '../../src/operations/wrapGovernance.js';
import { planWrapGovernanceLiquid } from '../../src/operations/wrapGovernanceLiquid.js';
import { planUnstakeAndWrapGovernance } from '../../src/operations/wrapGovernanceFromStake.js';
import { planTreasuryMigrationProposal } from '../../src/operations/treasuryMigrate.js';
import {
  SAFE_WALLET_ADDRESS,
  STAKING_PROXY_ADDRESS,
  TARGET_POOL_31,
  ZRX_TOKEN_ADDRESS,
} from '../../src/config/constants.js';
import { resolveTargetPools } from '../../src/config/pools.js';
import { encodeApproveZrxToErc20Proxy } from '../../src/contracts/zrx.js';
import { simulateSafePlans } from '../../src/safe/transaction.js';
import { readStakeDelegatedToPool } from '../../src/contracts/staking.js';
import type { OperationPlan } from '../../src/operations/types.js';

const FORK_URL = process.env.RPC_URL;

describe.skipIf(!FORK_URL)('integration: mainnet fork', () => {
  let fork: ForkInstance;
  let snapshotId: `0x${string}`;

  beforeAll(async () => {
    if (!FORK_URL) throw new Error('RPC_URL required');
    fork = await startAnvilFork(FORK_URL);
    await seedTestStake(fork);
    snapshotId = await fork.testClient.snapshot();
  }, 120_000);

  beforeEach(async () => {
    await fork.testClient.revert({ id: snapshotId });
    // Anvil consumes the snapshot on revert, so take a fresh one for the next test.
    snapshotId = await fork.testClient.snapshot();
  });

  afterAll(async () => {
    await fork?.stop();
  }, 30_000);

  it('builds undelegate-all calldata for the seeded test account', async () => {
    const result = await planUndelegateAll(fork.publicClient, TEST_EOA_ADDRESS);
    expect(result.result.plans.length).toBe(1);
    expect(result.innerCalls.length).toBeGreaterThan(0);
    expect(result.totalUndelegatedAmount).toBeGreaterThan(0n);
  });

  it('simulates undelegate-all from the test account without revert', async () => {
    const { result } = await planUndelegateAll(fork.publicClient, TEST_EOA_ADDRESS);
    const plan = result.plans[0];
    const gas = await fork.publicClient.estimateGas({
      account: TEST_EOA_ADDRESS,
      to: plan.to,
      value: plan.value,
      data: plan.data,
    });
    expect(gas).toBeGreaterThan(0n);
  });

  it('executes undelegate-all on the fork', async () => {
    const walletClient = createTestWalletClient(fork);
    const { result } = await planUndelegateAll(fork.publicClient, TEST_EOA_ADDRESS);
    for (const plan of result.plans) {
      const hash = await walletClient.sendTransaction({
        chain: mainnet,
        account: TEST_EOA_ADDRESS,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
      const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).toBe('success');
    }
  });

  it('cannot unstake immediately after undelegating', async () => {
    const walletClient = createTestWalletClient(fork);
    const { result } = await planUndelegateAll(fork.publicClient, TEST_EOA_ADDRESS);
    await walletClient.sendTransaction({
      chain: mainnet,
      account: TEST_EOA_ADDRESS,
      to: result.plans[0].to,
      value: result.plans[0].value,
      data: result.plans[0].data,
    });

    await expect(
      planUnstake(fork.publicClient, TEST_EOA_ADDRESS, parseEther('100'))
    ).rejects.toThrow(/Insufficient undelegated stake/);
  });

  it('advances epoch via endEpoch and then atomically unstakes + wraps to wZRX', async () => {
    const walletClient = createTestWalletClient(fork);

    // 1. Undelegate.
    const { result: undelegateResult } = await planUndelegateAll(
      fork.publicClient,
      TEST_EOA_ADDRESS
    );
    await walletClient.sendTransaction({
      chain: mainnet,
      account: TEST_EOA_ADDRESS,
      to: undelegateResult.plans[0].to,
      value: undelegateResult.plans[0].value,
      data: undelegateResult.plans[0].data,
    });

    // 2. End the epoch so the undelegation becomes withdrawable.
    await endEpochOnFork(fork);

    // 3. Build and execute unstake + wrap in one flow.
    const wrapAmount = parseEther('100');
    const { plans } = await planUnstakeAndWrapGovernance(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      wrapAmount,
      TEST_EOA_ADDRESS
    );
    expect(plans.length).toBe(5);

    for (const plan of plans) {
      const hash = await walletClient.sendTransaction({
        chain: mainnet,
        account: TEST_EOA_ADDRESS,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
      const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).toBe('success');
    }
  });

  it('wraps liquid ZRX into wZRX governance (storage override)', async () => {
    await setZrxBalance(fork, TEST_EOA_ADDRESS, parseEther('100'));
    const { plans } = await planWrapGovernanceLiquid(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      parseEther('50'),
      TEST_EOA_ADDRESS
    );
    expect(plans.length).toBe(4);

    const walletClient = createTestWalletClient(fork);
    for (const plan of plans) {
      const hash = await walletClient.sendTransaction({
        chain: mainnet,
        account: TEST_EOA_ADDRESS,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
      const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).toBe('success');
    }
  });

  it('executes the full wrap-governance flow on the fork', async () => {
    const walletClient = createTestWalletClient(fork);

    // Advance time far enough that endEpoch() can be called.
    const epochDuration = await fork.publicClient.readContract({
      address: STAKING_PROXY_ADDRESS,
      abi: [{ type: 'function', name: 'epochDurationInSeconds', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
      functionName: 'epochDurationInSeconds',
    });
    await fork.testClient.increaseTime({ seconds: Number(epochDuration) + 200 });
    await fork.testClient.mine({ blocks: 1 });

    const wrapAmount = parseEther('100');
    const { plans } = await planWrapGovernance(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      wrapAmount,
      TEST_EOA_ADDRESS
    );
    expect(plans.length).toBe(7);

    for (const plan of plans) {
      const hash = await walletClient.sendTransaction({
        chain: mainnet,
        account: TEST_EOA_ADDRESS,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
      const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).toBe('success');
    }
  });

  it('builds a treasury migration proposal and checks proposer voting power', async () => {
    await expect(
      planTreasuryMigrationProposal(fork.publicClient, TEST_EOA_ADDRESS)
    ).rejects.toThrow(/voting power|proposal threshold/i);
  });

  it('builds redelegate calldata for the test account', async () => {
    const pools = resolveTargetPools();
    const { result } = await planUndelegateAndDelegate(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      parseEther('10'),
      pools
    );
    expect(result.plans.length).toBe(1);
  });

  it('builds stake-and-delegate calldata for the test account', async () => {
    const pools = resolveTargetPools();
    const result = await planStakeAndDelegate(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      parseEther('1'),
      pools
    );
    expect(result.plans.length).toBeGreaterThanOrEqual(1);
    const stakingPlan = result.plans.find(
      (p) => p.description.includes('Stake') && p.description.includes('delegate')
    );
    expect(stakingPlan).toBeDefined();
  });

  it('executes stake-and-delegate on the fork', async () => {
    const walletClient = createTestWalletClient(fork);
    const pools = resolveTargetPools();
    const result = await planStakeAndDelegate(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      parseEther('10'),
      pools
    );
    for (const plan of result.plans) {
      const hash = await walletClient.sendTransaction({
        chain: mainnet,
        account: TEST_EOA_ADDRESS,
        to: plan.to,
        value: plan.value,
        data: plan.data,
      });
      const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).toBe('success');
    }
  });

  it('simulates Safe inner calls from the Safe address without revert', async () => {
    const plan: OperationPlan = {
      to: ZRX_TOKEN_ADDRESS,
      value: 0n,
      data: encodeApproveZrxToErc20Proxy(0n),
      description: 'Approve 0 ZRX from Safe (simulation smoke test)',
    };
    await simulateSafePlans(fork.publicClient, SAFE_WALLET_ADDRESS, [plan]);
  });

  it('reads delegated stake for the Safe from on-chain state', async () => {
    const balance = await readStakeDelegatedToPool(
      fork.publicClient,
      SAFE_WALLET_ADDRESS,
      TARGET_POOL_31
    );
    expect(balance.currentEpochBalance).toBeGreaterThan(0n);
  });
});
