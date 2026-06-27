/**
 * Integration tests against a mainnet fork.
 *
 * Run with `yarn test:foundry` (loads `.env` automatically). They start a local
 * anvil mainnet fork, seed a test account with ZRX stake, and exercise the
 * full rebalance / migration flows end-to-end with on-chain state assertions.
 *
 * GitHub source: tests/integration/fork.test.ts
 */

import { describe, expect, it, beforeAll, beforeEach, afterAll } from 'vitest';
import { parseEther, type Account, type Address } from 'viem';
import { mainnet } from 'viem/chains';
import { startAnvilFork, type ForkInstance } from './anvil.js';
import {
  addDelegation,
  advanceEpochAndMine,
  createTestWalletClient,
  createWalletClientForAccount,
  endEpochOnFork,
  getAnvilAccount,
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
import { planRedelegateAll } from '../../src/operations/redelegateAll.js';
import { planRedelegateAmount } from '../../src/operations/redelegateAmount.js';
import { planWrapGovernanceExcludePools } from '../../src/operations/wrapGovernanceExcludePools.js';
import { planSplitWrapGovernance } from './splitWrap.js';
import {
  SAFE_WALLET_ADDRESS,
  STAKING_PROXY_ADDRESS,
  TARGET_POOL_31,
  TARGET_POOL_48,
  TARGET_POOL_34,
  ZRX_TOKEN_ADDRESS,
} from '../../src/config/constants.js';
import { resolveTargetPools } from '../../src/config/pools.js';
import { encodeApproveZrxToErc20Proxy } from '../../src/contracts/zrx.js';
import { simulateSafePlans } from '../../src/safe/transaction.js';
import { readOwnerStakeStatuses, readStakeDelegatedToPool } from '../../src/contracts/staking.js';
import { readWzrxBalance, readWzrxDelegatee } from '../../src/contracts/wzrx.js';
import type { OperationPlan } from '../../src/operations/types.js';

const FORK_URL = process.env.RPC_URL;

const EXTRA_POOL =
  '0x0000000000000000000000000000000000000000000000000000000000000032' as `0x${string}`;

async function sendPlan(
  fork: ForkInstance,
  walletClient: ReturnType<typeof createTestWalletClient>,
  plan: OperationPlan,
  account: Address | Account = TEST_EOA_ADDRESS
) {
  const hash = await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: plan.to,
    value: plan.value,
    data: plan.data,
  });
  const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
  expect(receipt.status).toBe('success');
}

async function readPoolBalances(
  fork: ForkInstance,
  account: `0x${string}`,
  poolIds: `0x${string}`[]
) {
  return Promise.all(
    poolIds.map((poolId) => readStakeDelegatedToPool(fork.publicClient, account, poolId))
  );
}

function sumCurrentEpoch(balances: Awaited<ReturnType<typeof readPoolBalances>>): bigint {
  return balances.reduce((a, b) => a + b.currentEpochBalance, 0n);
}

async function readCurrentEpochPoolBalances(
  fork: ForkInstance,
  account: `0x${string}`,
  poolIds: `0x${string}`[]
): Promise<Record<string, bigint>> {
  const balances = await readPoolBalances(fork, account, poolIds);
  const map: Record<string, bigint> = {};
  poolIds.forEach((poolId, i) => {
    map[poolId.toLowerCase()] = balances[i].currentEpochBalance;
  });
  return map;
}

describe('integration: mainnet fork', () => {
  let fork: ForkInstance;
  let snapshotId: `0x${string}`;

  beforeAll(async () => {
    if (!FORK_URL) {
      throw new Error(
        'Fork integration tests require RPC_URL to be set as an environment variable'
      );
    }
    fork = await startAnvilFork(FORK_URL);
    await seedTestStake(fork);
    snapshotId = await fork.testClient.snapshot();
  }, 120_000);

  beforeEach(async () => {
    await fork.testClient.revert({ id: snapshotId });
    snapshotId = await fork.testClient.snapshot();
  });

  afterAll(async () => {
    await fork?.stop();
  }, 30_000);

  // ------------------------------------------------------------------------
  // Existing smoke tests
  // ------------------------------------------------------------------------

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

  it('cannot unstake immediately after undelegating', async () => {
    const walletClient = createTestWalletClient(fork);
    const { result } = await planUndelegateAll(fork.publicClient, TEST_EOA_ADDRESS);
    await sendPlan(fork, walletClient, result.plans[0]);

    await expect(
      planUnstake(fork.publicClient, TEST_EOA_ADDRESS, parseEther('100'))
    ).rejects.toThrow(/Insufficient undelegated stake/);
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

  // ------------------------------------------------------------------------
  // Test 1: undelegate all active stake and redelegate to target pools
  // ------------------------------------------------------------------------

  it('redelegates all active stake to the target pools via moveStake', async () => {
    const walletClient = createTestWalletClient(fork);
    const targetPools = [...resolveTargetPools(), EXTRA_POOL];

    // The default fixture has 500 ZRX delegated to pool 0x31. Add another 300
    // to pool 0x48 so the active stake is spread across two pools, then roll
    // the epoch so the new delegation becomes active.
    await addDelegation(fork, TARGET_POOL_48, parseEther('300'));
    await endEpochOnFork(fork);

    const beforeAll = await readPoolBalances(fork, TEST_EOA_ADDRESS, targetPools);
    const originalTotal = sumCurrentEpoch(beforeAll);
    expect(originalTotal).toBe(parseEther('800'));

    const { result: redelegateResult } = await planRedelegateAll(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      targetPools
    );
    const plans = redelegateResult.plans;
    expect(plans.length).toBe(1);

    await sendPlan(fork, walletClient, plans[0]);
    await endEpochOnFork(fork);

    const after = await readCurrentEpochPoolBalances(fork, TEST_EOA_ADDRESS, targetPools);
    const afterTotal = Object.values(after).reduce((a, b) => a + b, 0n);

    expect(afterTotal).toBe(originalTotal);
    for (const poolId of targetPools) {
      expect(after[poolId.toLowerCase()]).toBeGreaterThan(0n);
    }
  });

  // ------------------------------------------------------------------------
  // Test 2: redelegate a specific net amount to the target pools
  // ------------------------------------------------------------------------

  it('redelegates a specific net amount to the target pools', async () => {
    const walletClient = createTestWalletClient(fork);
    const targetPools = resolveTargetPools();

    // The default fixture has 500 ZRX delegated to pool 0x31 (a target pool).
    // Request a lower target total; the excess must move to undelegated stake.
    const targetAmount = parseEther('300');
    const { result: redelegateResult, currentTargetAmount, movedAmount } =
      await planRedelegateAmount(
        fork.publicClient,
        TEST_EOA_ADDRESS,
        targetAmount,
        targetPools
      );
    const plans = redelegateResult.plans;
    expect(plans.length).toBe(1);
    expect(currentTargetAmount).toBe(parseEther('500'));
    expect(movedAmount).toBe(parseEther('200'));

    await sendPlan(fork, walletClient, plans[0]);
    await endEpochOnFork(fork);

    const targetBalances = await readPoolBalances(fork, TEST_EOA_ADDRESS, targetPools);
    expect(sumCurrentEpoch(targetBalances)).toBe(targetAmount);

    // The excess should now be undelegated.
    const statuses = await readOwnerStakeStatuses(fork.publicClient, TEST_EOA_ADDRESS);
    expect(statuses.undelegated.currentEpochBalance).toBe(parseEther('200'));
  });

  // ------------------------------------------------------------------------
  // Test 3: stake new ZRX, delegate to pools, roll epoch, verify active stake
  // ------------------------------------------------------------------------

  it('stakes new ZRX, delegates to pools, rolls epoch, and verifies active stake', async () => {
    const walletClient = createTestWalletClient(fork);
    const targetPools = [...resolveTargetPools(), EXTRA_POOL];
    const stakeAmount = parseEther('100');

    const before = await readCurrentEpochPoolBalances(
      fork,
      TEST_EOA_ADDRESS,
      targetPools
    );

    const result = await planStakeAndDelegate(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      stakeAmount,
      targetPools
    );
    for (const plan of result.plans) {
      await sendPlan(fork, walletClient, plan);
    }

    await endEpochOnFork(fork);

    const after = await readCurrentEpochPoolBalances(
      fork,
      TEST_EOA_ADDRESS,
      targetPools
    );

    const perPool = stakeAmount / BigInt(targetPools.length);
    const remainder = stakeAmount - perPool * BigInt(targetPools.length);

    for (const poolId of targetPools) {
      const increase =
        after[poolId.toLowerCase()] - before[poolId.toLowerCase()];
      // The first pools receive the base share; the last pool also receives the remainder.
      const expected =
        poolId.toLowerCase() === targetPools[targetPools.length - 1].toLowerCase()
          ? perPool + remainder
          : perPool;
      expect(increase).toBe(expected);
    }
  });

  // ------------------------------------------------------------------------
  // Test 4: wrap ZRX to wZRX and delegate split shares to pool operators
  // ------------------------------------------------------------------------

  it('wraps ZRX to wZRX and delegates split shares to pool operators', async () => {
    const stakerWallet = createTestWalletClient(fork);
    const targetPools = resolveTargetPools();
    const wrapAmount = parseEther('30');

    // The default fixture leaves 500 ZRX liquid; no extra balance setup needed.
    const recipients = targetPools.map((_, i) => getAnvilAccount(i + 1).address);
    const { stakerPlans, recipientPlans, shares, delegatees } =
      planSplitWrapGovernance(TEST_EOA_ADDRESS, wrapAmount, targetPools, recipients);

    for (const plan of stakerPlans) {
      await sendPlan(fork, stakerWallet, plan);
    }

    for (let i = 0; i < recipients.length; i++) {
      const recipient = getAnvilAccount(i + 1);
      const recipientWallet = createWalletClientForAccount(fork, recipient);
      await sendPlan(
        fork,
        recipientWallet as unknown as ReturnType<typeof createTestWalletClient>,
        recipientPlans[i],
        recipient
      );

      const balance = await readWzrxBalance(fork.publicClient, recipient.address);
      expect(balance).toBe(shares[i]);

      const delegatee = await readWzrxDelegatee(fork.publicClient, recipient.address);
      expect(delegatee.toLowerCase()).toBe(delegatees[i].toLowerCase());
    }
  });

  // ------------------------------------------------------------------------
  // Test 5: undelegate from non-target pools, wait epoch, roll + unstake + wrap
  // ------------------------------------------------------------------------

  it('undelegates from non-target pools and atomically unstake+wraps after epoch rollover', async () => {
    const walletClient = createTestWalletClient(fork);

    // Default fixture: 500 delegated to pool 0x31. Add 200 to pool 0x32 and
    // 300 to pool 0x34, roll the epoch so they become active, then exclude
    // 0x31 so the source pools are 0x32 + 0x34.
    await addDelegation(fork, EXTRA_POOL, parseEther('200'));
    await addDelegation(fork, TARGET_POOL_34, parseEther('300'));
    await endEpochOnFork(fork);

    const wrapAmount = parseEther('400');
    const excludePools = [TARGET_POOL_31];

    // Make the epoch eligible to end again before executing the plan.
    await advanceEpochAndMine(fork);

    const { plans } = await planWrapGovernanceExcludePools(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      wrapAmount,
      excludePools,
      TEST_EOA_ADDRESS
    );
    expect(plans.length).toBe(7);

    for (const plan of plans) {
      await sendPlan(fork, walletClient, plan);
    }

    const excluded = await readStakeDelegatedToPool(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      TARGET_POOL_31
    );
    expect(excluded.currentEpochBalance).toBe(parseEther('500'));

    const nonExcludedTotal = sumCurrentEpoch(
      await readPoolBalances(fork, TEST_EOA_ADDRESS, [EXTRA_POOL, TARGET_POOL_34])
    );
    expect(nonExcludedTotal).toBe(parseEther('100'));

    const remainingExtra = await readStakeDelegatedToPool(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      EXTRA_POOL
    );
    expect(remainingExtra.currentEpochBalance).toBe(parseEther('40'));

    const remaining34 = await readStakeDelegatedToPool(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      TARGET_POOL_34
    );
    expect(remaining34.currentEpochBalance).toBe(parseEther('60'));

    const wzrxBalance = await readWzrxBalance(fork.publicClient, TEST_EOA_ADDRESS);
    expect(wzrxBalance).toBe(wrapAmount);
  });

  // ------------------------------------------------------------------------
  // Legacy wrap flows (kept for coverage)
  // ------------------------------------------------------------------------

  it('advances epoch via endEpoch and then atomically unstakes + wraps to wZRX', async () => {
    const walletClient = createTestWalletClient(fork);

    const { result: undelegateResult } = await planUndelegateAll(
      fork.publicClient,
      TEST_EOA_ADDRESS
    );
    await sendPlan(fork, walletClient, undelegateResult.plans[0]);

    await endEpochOnFork(fork);

    const wrapAmount = parseEther('100');
    const { plans } = await planUnstakeAndWrapGovernance(
      fork.publicClient,
      TEST_EOA_ADDRESS,
      wrapAmount,
      TEST_EOA_ADDRESS
    );
    expect(plans.length).toBe(5);

    for (const plan of plans) {
      await sendPlan(fork, walletClient, plan);
    }

    const wzrxBalance = await readWzrxBalance(fork.publicClient, TEST_EOA_ADDRESS);
    expect(wzrxBalance).toBe(wrapAmount);
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
      await sendPlan(fork, walletClient, plan);
    }

    const wzrxBalance = await readWzrxBalance(fork.publicClient, TEST_EOA_ADDRESS);
    expect(wzrxBalance).toBe(parseEther('50'));

    const delegatee = await readWzrxDelegatee(fork.publicClient, TEST_EOA_ADDRESS);
    expect(delegatee.toLowerCase()).toBe(TEST_EOA_ADDRESS.toLowerCase());
  });

  it('executes the full wrap-governance flow on the fork', async () => {
    const walletClient = createTestWalletClient(fork);

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
      await sendPlan(fork, walletClient, plan);
    }

    const wzrxBalance = await readWzrxBalance(fork.publicClient, TEST_EOA_ADDRESS);
    expect(wzrxBalance).toBe(wrapAmount);
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
});
