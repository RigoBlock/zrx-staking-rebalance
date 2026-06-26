/**
 * Interactive CLI menu for users who prefer guided input over positional args.
 *
 * GitHub source: src/cli/menu.ts
 */

import inquirer from 'inquirer';
import type { Hex } from 'viem';
import { validatePoolIds } from '../config/pools.js';
import { parseZrx } from '../utils/amounts.js';

export interface MenuResult {
  command: string;
  args: string[];
  options: Record<string, string | boolean>;
}

const OPERATIONS = [
  { name: 'Undelegate all stake', value: 'undelegate-all' },
  { name: 'Stake new ZRX', value: 'stake-new' },
  { name: 'Delegate equally across target pools', value: 'delegate-equal' },
  { name: 'Redelegate (undelegate all + delegate equally)', value: 'redelegate' },
  { name: 'Stake and delegate equally', value: 'stake-and-delegate' },
  { name: 'Unstake undelegated ZRX', value: 'unstake' },
  { name: 'Full legacy-stake migration to wZRX governance', value: 'wrap-governance' },
  { name: 'Wrap liquid ZRX to wZRX governance', value: 'wrap-governance-liquid' },
  { name: 'Propose old-treasury migration', value: 'treasury-migrate-propose' },
  { name: 'Execute old-treasury migration proposal', value: 'treasury-migrate-execute' },
];

export async function runInteractiveMenu(): Promise<MenuResult> {
  const { operation } = await inquirer.prompt([
    {
      type: 'list',
      name: 'operation',
      message: 'What do you want to do?',
      choices: OPERATIONS,
    },
  ]);

  const { wallet } = await inquirer.prompt([
    {
      type: 'input',
      name: 'wallet',
      message: 'Wallet address:',
      validate: (input: string) =>
        /^0x[a-fA-F0-9]{40}$/.test(input) || 'Enter a valid Ethereum address',
    },
  ]);

  const args: string[] = [wallet];
  const options: Record<string, string | boolean> = {};

  if (
    operation !== 'undelegate-all'
  ) {
    const { amount } = await inquirer.prompt([
      {
        type: 'input',
        name: 'amount',
        message: 'Amount of ZRX (human readable, e.g. 1000000):',
        validate: (input: string) => {
          try {
            parseZrx(input);
            return true;
          } catch {
            return 'Enter a valid ZRX amount';
          }
        },
      },
    ]);
    args.push(amount);
  }

  if (
    operation === 'delegate-equal' ||
    operation === 'redelegate' ||
    operation === 'stake-and-delegate'
  ) {
    const { addExtraPool } = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'addExtraPool',
        message: 'Add a 4th target pool id?',
        default: false,
      },
    ]);

    if (addExtraPool) {
      const { extraPool } = await inquirer.prompt([
        {
          type: 'input',
          name: 'extraPool',
          message: 'Extra pool id (bytes32):',
          validate: (input: string) => {
            try {
              validatePoolIds([input as Hex]);
              return true;
            } catch {
              return 'Enter a valid bytes32 pool id';
            }
          },
        },
      ]);
      args.push(extraPool);
    }
  }

  if (
    operation === 'wrap-governance' ||
    operation === 'wrap-governance-liquid'
  ) {
    const { delegatee } = await inquirer.prompt([
      {
        type: 'input',
        name: 'delegatee',
        message: 'Address to delegate wZRX voting power to:',
        validate: (input: string) =>
          /^0x[a-fA-F0-9]{40}$/.test(input) || 'Enter a valid Ethereum address',
      },
    ]);
    options.delegatee = delegatee;
  }

  if (operation === 'treasury-migrate-propose') {
    const { operatedPools } = await inquirer.prompt([
      {
        type: 'input',
        name: 'operatedPools',
        message: 'Operated pool ids (comma-separated bytes32, or leave blank):',
        default: '',
      },
    ]);
    const pools = (operatedPools as string)
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    if (pools.length > 0) {
      args.push('--operated-pools', ...pools);
    }
  }

  if (operation === 'treasury-migrate-execute') {
    const { proposalId } = await inquirer.prompt([
      {
        type: 'input',
        name: 'proposalId',
        message: 'Proposal ID:',
        validate: (input: string) => /^\d+$/.test(input) || 'Enter a numeric proposal ID',
      },
    ]);
    args.push(String(proposalId));
  }

  const { dryRun } = await inquirer.prompt([
    {
      type: 'confirm',
      name: 'dryRun',
      message: 'Run in dry-run mode (simulate only, do not send)?',
      default: true,
    },
  ]);
  options.dryRun = dryRun;

  return { command: operation, args, options };
}
