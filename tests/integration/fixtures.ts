/**
 * Fork test fixtures.
 *
 * Creates a funded test EOA on the anvil fork, stakes ZRX, and delegates it
 * so the operation-plan tests have real on-chain state to exercise.
 *
 * GitHub source: tests/integration/fixtures.ts
 */

import {
  createWalletClient,
  encodeAbiParameters,
  http,
  keccak256,
  padHex,
  parseEther,
  toHex,
  type Address,
  type WalletClient,
} from 'viem';
import { privateKeyToAccount, mnemonicToAccount } from 'viem/accounts';
import { mainnet } from 'viem/chains';
import {
  STAKING_PROXY_ADDRESS,
  TARGET_POOL_31,
  ZRX_TOKEN_ADDRESS,
} from '../../src/config/constants.js';
import { encodeApproveZrxToErc20Proxy } from '../../src/contracts/zrx.js';
import { encodeDelegateToPool, encodeStake } from '../../src/contracts/staking.js';
import { encodeFunctionData, parseAbi } from 'viem';
import type { ForkInstance } from './anvil.js';

/** Anvil default account #0 — has plenty of ETH on a fresh fork. */
export const TEST_EOA_PRIVATE_KEY: Address =
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' as Address;

export const TEST_EOA_ADDRESS: Address =
  '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' as Address;

/**
 * ZRX balance mapping lives at storage slot 0 in the ZRXToken contract
 * (mapping(address => uint256) balances;).
 */
function getZrxBalanceStorageSlot(account: Address): `0x${string}` {
  return keccak256(
    encodeAbiParameters(
      [{ type: 'address' }, { type: 'uint256' }],
      [account, 0n]
    )
  );
}

/** Give the test account a ZRX balance by writing the ERC-20 balance slot. */
export async function setZrxBalance(
  fork: ForkInstance,
  account: Address,
  amount: bigint
): Promise<void> {
  const slot = getZrxBalanceStorageSlot(account);
  await fork.testClient.setStorageAt({
    address: ZRX_TOKEN_ADDRESS,
    index: slot,
    value: padHex(toHex(amount), { size: 32 }),
  });
}

export function createTestWalletClient(fork: ForkInstance): WalletClient {
  const account = privateKeyToAccount(TEST_EOA_PRIVATE_KEY);
  return createWalletClient({
    chain: mainnet,
    transport: http(fork.rpcUrl),
    account,
  });
}

const ANVIL_MNEMONIC = 'test test test test test test test test test test test junk';

/** Return one of Anvil's deterministic accounts by index. */
export function getAnvilAccount(index: number) {
  // Anvil derives accounts by address index, not account index.
  return mnemonicToAccount(ANVIL_MNEMONIC, { addressIndex: index });
}

/** Create a wallet client for an arbitrary account on the fork. */
export function createWalletClientForAccount(
  fork: ForkInstance,
  account: ReturnType<typeof getAnvilAccount>
): WalletClient {
  return createWalletClient({
    chain: mainnet,
    transport: http(fork.rpcUrl),
    account,
  });
}

/**
 * Advance the fork timestamp past the current epoch end and mine a block.
 * This does NOT call endEpoch(); it only makes the epoch eligible to end.
 */
export async function advanceEpochAndMine(fork: ForkInstance): Promise<void> {
  const epochDuration = await fork.publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: parseAbi(['function epochDurationInSeconds() view returns (uint256)']),
    functionName: 'epochDurationInSeconds',
  });
  await fork.testClient.increaseTime({ seconds: Number(epochDuration) + 200 });
  await fork.testClient.mine({ blocks: 1 });
}

/**
 * Stake additional liquid ZRX and delegate it to a single pool.
 * Useful for tests that need stake spread across multiple pools on top of the
 * default `seedTestStake` fixture.
 */
export async function addDelegation(
  fork: ForkInstance,
  poolId: `0x${string}`,
  amount: bigint
): Promise<void> {
  const walletClient = createTestWalletClient(fork);
  const account = walletClient.account!.address;

  const approveHash = await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: ZRX_TOKEN_ADDRESS,
    data: encodeApproveZrxToErc20Proxy(amount),
  });
  const approveReceipt = await fork.publicClient.waitForTransactionReceipt({
    hash: approveHash,
  });
  if (approveReceipt.status !== 'success') {
    throw new Error(`addDelegation approve failed: ${approveReceipt.status}`);
  }

  const stakeHash = await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeStake(amount),
  });
  const stakeReceipt = await fork.publicClient.waitForTransactionReceipt({
    hash: stakeHash,
  });
  if (stakeReceipt.status !== 'success') {
    throw new Error(`addDelegation stake failed: ${stakeReceipt.status}`);
  }

  const delegateHash = await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeDelegateToPool(poolId, amount),
  });
  const delegateReceipt = await fork.publicClient.waitForTransactionReceipt({
    hash: delegateHash,
  });
  if (delegateReceipt.status !== 'success') {
    throw new Error(`addDelegation delegate failed: ${delegateReceipt.status}`);
  }
}

/**
 * Seed the test account with ZRX, stake the requested amount, and delegate
 * across the provided pools. Then advance the epoch via storage override so
 * the delegation becomes active for reads.
 */
export async function seedStakeInPools(
  fork: ForkInstance,
  poolAmounts: { poolId: `0x${string}`; amount: bigint }[]
): Promise<void> {
  const walletClient = createTestWalletClient(fork);
  const account = walletClient.account!.address;

  const total = poolAmounts.reduce((a, b) => a + b.amount, 0n);

  await setZrxBalance(fork, account, total);

  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: ZRX_TOKEN_ADDRESS,
    data: encodeApproveZrxToErc20Proxy(total),
  });

  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeStake(total),
  });

  for (const { poolId, amount } of poolAmounts) {
    await walletClient.sendTransaction({
      chain: mainnet,
      account,
      to: STAKING_PROXY_ADDRESS,
      data: encodeDelegateToPool(poolId, amount),
    });
  }

  // Advance epoch via storage override so currentEpochBalance reflects delegation.
  const block = await fork.publicClient.getBlock();
  const currentEpoch = await fork.publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: [{ type: 'function', name: 'currentEpoch', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
    functionName: 'currentEpoch',
  });
  await fork.testClient.setStorageAt({
    address: STAKING_PROXY_ADDRESS,
    index: padHex(toHex(12n), { size: 32 }),
    value: padHex(toHex((currentEpoch as bigint) + 1n), { size: 32 }),
  });
  await fork.testClient.setStorageAt({
    address: STAKING_PROXY_ADDRESS,
    index: padHex(toHex(13n), { size: 32 }),
    value: padHex(toHex(block.timestamp - 10n), { size: 32 }),
  });
}

/**
 * Fund the test account with ZRX, approve the ERC20 Asset Proxy, stake, and
 * delegate half to pool 0x31. Leaves the other half liquid.
 */
export async function seedTestStake(fork: ForkInstance): Promise<void> {
  const walletClient = createTestWalletClient(fork);
  const account = walletClient.account!.address;

  const total = parseEther('1000');
  const staked = parseEther('500');

  await setZrxBalance(fork, account, total);

  // Approve the ERC20 Asset Proxy so the ZRX Vault can pull ZRX on stake.
  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: ZRX_TOKEN_ADDRESS,
    data: encodeApproveZrxToErc20Proxy(total),
  });

  // Stake.
  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeStake(staked),
  });

  // Delegate staked amount to pool 0x31.
  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeDelegateToPool(TARGET_POOL_31, staked),
  });

  // Advance one epoch so currentEpochBalance reflects the delegated stake.
  // The TupleFixer helper checks currentEpochBalance > 0. We manipulate the
  // staking contract's `currentEpoch` (slot 12) and `currentEpochStartTimeInSeconds`
  // (slot 13) storage directly on the fork.
  const block = await fork.publicClient.getBlock();
  const currentEpoch = await fork.publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: [{ type: 'function', name: 'currentEpoch', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
    functionName: 'currentEpoch',
  });
  await fork.testClient.setStorageAt({
    address: STAKING_PROXY_ADDRESS,
    index: padHex(toHex(12n), { size: 32 }),
    value: padHex(toHex((currentEpoch as bigint) + 1n), { size: 32 }),
  });
  await fork.testClient.setStorageAt({
    address: STAKING_PROXY_ADDRESS,
    index: padHex(toHex(13n), { size: 32 }),
    value: padHex(toHex(block.timestamp - 10n), { size: 32 }),
  });
}

/**
 * Advance the staking epoch by calling `endEpoch()` on the fork.
 * Increases the block time by one epoch duration, mines a block, and then
 * sends the `endEpoch()` transaction.
 */
export async function endEpochOnFork(fork: ForkInstance): Promise<void> {
  const walletClient = createTestWalletClient(fork);
  const account = walletClient.account!.address;
  const epochDuration = await fork.publicClient.readContract({
    address: STAKING_PROXY_ADDRESS,
    abi: parseAbi(['function epochDurationInSeconds() view returns (uint256)']),
    functionName: 'epochDurationInSeconds',
  });
  await fork.testClient.increaseTime({ seconds: Number(epochDuration) + 100 });
  await fork.testClient.mine({ blocks: 1 });
  await walletClient.sendTransaction({
    chain: mainnet,
    account,
    to: STAKING_PROXY_ADDRESS,
    data: encodeFunctionData({
      abi: parseAbi(['function endEpoch() returns (uint256)']),
      functionName: 'endEpoch',
    }),
  });
}
