/**
 * Shared operation types.
 *
 * GitHub source: src/operations/types.ts
 */

import type { Address, Hex } from 'viem';

/** A single on-chain action ready to be sent or wrapped in a Safe tx. */
export interface OperationPlan {
  to: Address;
  value: bigint;
  data: Hex;
  description: string;
}

/** Result of planning a rebalance operation. */
export interface OperationPlanResult {
  /** Plans that must be executed sequentially. For Safe they are MultiSent. */
  plans: OperationPlan[];
  /** Human-readable summary. */
  summary: string;
}
