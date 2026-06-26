/**
 * Shared TypeScript types for the ZRX staking rebalance CLI.
 *
 * GitHub source: src/types.ts
 */

import type { Address, Hex } from 'viem';

/** A single ZRX staking pool identifier (bytes32). */
export type PoolId = Hex;

/** Known target pool together with its operator. */
export interface StakingPool {
  poolId: PoolId;
  operator: Address;
  name: string;
}

/** Stake status used inside the 0x staking contract. */
export enum StakeStatus {
  UNDELEGATED = 0,
  DELEGATED = 1,
}

/** Tuple representation of a StakeInfo struct. */
export interface StakeInfo {
  status: StakeStatus;
  poolId: PoolId;
}

/** A decoded moveStake operation for human-readable previews. */
export interface MoveStakeOperation {
  from: StakeInfo;
  to: StakeInfo;
  amount: bigint;
}

/** Command context shared by most CLI handlers. */
export interface CommandContext {
  rpcUrl: string;
  chainId: number;
  dryRun: boolean;
}

/** Supported signer types. */
export type SignerMode = 'private-key' | 'ledger' | 'trezor' | 'safe';

/** Result of the TupleFixer encodeUndelegateAll query. */
export interface UndelegateAllCalldata {
  totalUndelegatedAmount: bigint;
  encodedCalls: Hex[];
}
