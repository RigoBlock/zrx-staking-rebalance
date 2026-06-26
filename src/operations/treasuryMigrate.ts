/**
 * Operation: migrate old 0x ZrxTreasury assets to the new governance treasury.
 *
 * Because the old treasury can only act through passed proposals, this planner
 * creates a `ZrxTreasury.propose(...)` call. The actual asset movement happens
 * later when the proposal passes and `execute(...)` is called.
 *
 * GitHub source: src/operations/treasuryMigrate.ts
 */

import type { Address, Hex, PublicClient } from 'viem';
import { OLD_ZRX_TREASURY_ADDRESS } from '../config/constants.js';
import {
  buildTreasuryMigrationActions,
  encodeTreasuryExecute,
  encodeTreasuryPropose,
  readTreasuryBalances,
  readTreasuryThresholds,
  readTreasuryVotingPower,
  type ProposedAction,
  type TreasuryBalances,
} from '../contracts/treasury.js';
import { readEpochInfo } from '../contracts/staking.js';
import { formatZrx } from '../utils/amounts.js';
import type { OperationPlan, OperationPlanResult } from './types.js';

export interface TreasuryMigrationPlan extends OperationPlanResult {
  proposalId?: bigint;
  actions: ProposedAction[];
  executionEpoch: bigint;
}

function formatToken(name: string, amount: bigint): string {
  return `${formatZrx(amount)} ${name}`;
}

function hasAnyBalance(balances: TreasuryBalances): boolean {
  return balances.zrx > 0n || balances.wCelo > 0n || balances.matic > 0n;
}

/**
 * Build a proposal to migrate all old-treasury ZRX, wCELO, and MATIC→POL to the
 * new governance treasury.
 */
export async function planTreasuryMigrationProposal(
  publicClient: PublicClient,
  proposer: Address,
  operatedPoolIds: Hex[] = []
): Promise<TreasuryMigrationPlan> {
  const [balances, thresholds, epochInfo] = await Promise.all([
    readTreasuryBalances(publicClient),
    readTreasuryThresholds(publicClient),
    readEpochInfo(publicClient),
  ]);

  if (!hasAnyBalance(balances)) {
    throw new Error('Old treasury has zero ZRX, wCELO, and MATIC balances; nothing to migrate.');
  }

  const votingPower = await readTreasuryVotingPower(
    publicClient,
    proposer,
    operatedPoolIds
  );

  if (votingPower < thresholds.proposalThreshold) {
    throw new Error(
      `Proposer voting power ${formatZrx(
        votingPower
      )} is below the proposal threshold ${formatZrx(
        thresholds.proposalThreshold
      )}.`
    );
  }

  const actions = buildTreasuryMigrationActions(balances);
  if (actions.length === 0) {
    throw new Error('No migration actions to propose after filtering zero balances.');
  }

  const executionEpoch = epochInfo.currentEpoch + 2n;

  const description =
    'Migrate old ZRX treasury assets (ZRX, wCELO, MATIC->POL) to the new 0x governance treasury.';

  const plan: OperationPlan = {
    to: OLD_ZRX_TREASURY_ADDRESS,
    value: 0n,
    data: encodeTreasuryPropose(actions, executionEpoch, description, operatedPoolIds),
    description: `Propose treasury migration (actions=${actions.length}, executionEpoch=${executionEpoch.toString()})`,
  };

  return {
    plans: [plan],
    actions,
    executionEpoch,
    summary: `Treasury migration proposal: ${[
      balances.zrx > 0n ? formatToken('ZRX', balances.zrx) : '',
      balances.wCelo > 0n ? formatToken('wCELO', balances.wCelo) : '',
      balances.matic > 0n ? formatToken('MATIC', balances.matic) : '',
    ]
      .filter(Boolean)
      .join(', ')}`,
  };
}

/**
 * Build an execute call for an existing treasury migration proposal.
 *
 * The actions must match the proposal's actions hash exactly, so this rebuilds
 * the same migration actions from current balances. Balances must not change
 * between propose and execute.
 */
export async function planTreasuryMigrationExecution(
  publicClient: PublicClient,
  proposalId: bigint
): Promise<OperationPlanResult> {
  const balances = await readTreasuryBalances(publicClient);
  if (!hasAnyBalance(balances)) {
    throw new Error('Old treasury balances are zero; cannot rebuild migration actions.');
  }

  const actions = buildTreasuryMigrationActions(balances);
  const plan: OperationPlan = {
    to: OLD_ZRX_TREASURY_ADDRESS,
    value: 0n,
    data: encodeTreasuryExecute(proposalId, actions),
    description: `Execute treasury migration proposal ${proposalId.toString()}`,
  };

  return {
    plans: [plan],
    summary: `Execute treasury migration proposal ${proposalId.toString()}`,
  };
}
