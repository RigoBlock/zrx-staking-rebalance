#!/usr/bin/env node
/**
 * zrx-staking-rebalance CLI entry point.
 *
 * GitHub source: src/cli.ts
 */

import 'dotenv/config';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import type { Address, Hex, PublicClient } from 'viem';
import { CHAIN_ID_MAINNET, SAFE_TX_SERVICE_MAINNET } from './config/constants.js';
import { resolveTargetPools, validatePoolIds } from './config/pools.js';
import { createPublicClientFromUrl } from './ethereum/client.js';
import { wipeKitReference } from './safe/kit.js';
import {
  confirmSafeTransaction,
  createSafeBundle,
  executeSafeTransaction,
  getSafeTransaction,
  listPendingSafeTransactions,
  proposeSafeTransaction,
  simulateSafePlans,
} from './safe/transaction.js';
import { planUndelegateAll } from './operations/undelegateAll.js';
import { planStakeNew } from './operations/stakeNew.js';
import { parseZrx, planDelegateEqual } from './operations/delegateEqual.js';
import { planUndelegateAndDelegate } from './operations/undelegateAndDelegate.js';
import { planStakeAndDelegate } from './operations/stakeAndDelegate.js';
import { planWrapGovernance } from './operations/wrapGovernance.js';
import { planWrapGovernanceLiquid } from './operations/wrapGovernanceLiquid.js';
import {
  planTreasuryMigrationExecution,
  planTreasuryMigrationProposal,
} from './operations/treasuryMigrate.js';
import { planUnstake } from './operations/unstake.js';
import {
  loadSigner,
  printOperationPlans,
  resolveWallet,
  saveSafeProposalBackup,
  sendEoaTransaction,
} from './cli/helpers.js';
import { error, info, printSection, success, warning } from './utils/format.js';
import { runInteractiveMenu } from './cli/menu.js';
import type { SignerMode } from './types.js';

// --------------------------------------------------------------------------
// Shared yargs configuration
// --------------------------------------------------------------------------

const baseYargs = yargs(hideBin(process.argv))
  .scriptName('zrx-rebalance')
  .usage('$0 <command> [args]')
  .option('rpc-url', {
    type: 'string',
    description: 'Ethereum RPC endpoint (or set RPC_URL env var)',
    default: process.env.RPC_URL,
  })
  .option('dry-run', {
    type: 'boolean',
    description: 'Build, simulate, and preview transactions without sending',
    default: false,
  })
  .option('force-safe', {
    type: 'boolean',
    description: 'Force treating <wallet> as a Safe multisig',
    default: false,
  })
  .option('signer-mode', {
    type: 'string',
    choices: ['private-key', 'ledger', 'trezor'] as const,
    description: 'How to sign EOA transactions',
    default: 'private-key' as SignerMode,
  })
  .option('tx-service-url', {
    type: 'string',
    description: 'Safe Transaction Service URL',
    default: process.env.SAFE_TX_SERVICE_URL ?? SAFE_TX_SERVICE_MAINNET,
  })

  .help(false)
  .version(false)
  .option('help', { type: 'boolean', hidden: true });

// --------------------------------------------------------------------------
// Help command
// --------------------------------------------------------------------------

function showDetailedHelp(): void {
  printSection('zrx-staking-rebalance');
  console.log(
    'Terminal utility to reallocate ZRX stake across specific staking pools and\n' +
      'optionally migrate ZRX to the wZRX governance token.\n'
  );

  printSection('Commands');
  const commands = [
    ['undelegate-all <wallet>', 'Undelegate all active stake. Source: src/operations/undelegateAll.ts'],
    ['stake-new <wallet> <amount>', 'Stake new ZRX. Source: src/operations/stakeNew.ts'],
    ['delegate-equal <wallet> <amount> [pools...]', 'Delegate amount equally across pools. Source: src/operations/delegateEqual.ts'],
    ['redelegate <wallet> <amount> [pools...]', 'Undelegate all + delegate equally in one batch. Source: src/operations/undelegateAndDelegate.ts'],
    ['stake-and-delegate <wallet> <amount> [pools...]', 'Stake + delegate equally in one batch. Source: src/operations/stakeAndDelegate.ts'],
    ['unstake <wallet> <amount>', 'Unstake undelegated ZRX. Source: src/operations/unstake.ts'],
    ['wrap-governance <wallet> <amount> --delegatee <addr>', 'Full legacy-stake migration to wZRX. Source: src/operations/wrapGovernance.ts'],
    ['wrap-governance-liquid <wallet> <amount> --delegatee <addr>', 'Wrap liquid ZRX into wZRX governance. Source: src/operations/wrapGovernanceLiquid.ts'],
    ['treasury-migrate-propose <wallet> [--operated-pools..]', 'Propose migration of old treasury assets. Source: src/operations/treasuryMigrate.ts'],
    ['treasury-migrate-execute <wallet> <proposalId>', 'Execute a passed treasury migration proposal. Source: src/operations/treasuryMigrate.ts'],
    ['safe pending <safe>', 'List pending Safe transactions. Source: src/safe/transaction.ts'],
    ['safe show <safe> <safeTxHash>', 'Show a Safe transaction and its signatures. Source: src/safe/transaction.ts'],
    ['safe sign <safe> <safeTxHash>', 'Sign a pending Safe transaction. Source: src/safe/transaction.ts'],
    ['safe execute <safe> <safeTxHash>', 'Execute a fully signed Safe transaction. Source: src/safe/transaction.ts'],
    ['menu', 'Interactive menu to select operation and inputs. Source: src/cli/menu.ts'],
  ];
  for (const [cmd, desc] of commands) {
    console.log(`  ${cmd.padEnd(55)} ${desc}`);
  }

  printSection('Global options');
  console.log(
    '  --rpc-url <url>              Ethereum RPC endpoint\n' +
      '  --dry-run                    Build, simulate, and preview; do not send\n' +
      '  --force-safe                 Force Safe multisig workflow\n' +
      '  --signer-mode <mode>         private-key (prompted, hidden) | ledger | trezor\n' +
      '  --tx-service-url <url>       Safe Transaction Service URL\n'
  );

  printSection('Examples');
  console.log(
    '  yarn cli help\n' +
      '  yarn cli undelegate-all 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B --dry-run\n' +
      '  yarn cli stake-new 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 1000000\n' +
      '  yarn cli redelegate 0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B 3000000\n' +
      '  yarn cli safe pending 0x5775afA796818ADA27b09FaF5c90d101f04eF600\n' +
      '  yarn cli safe sign 0x5775afA796818ADA27b09FaF5c90d101f04eF600 <safeTxHash>\n'
  );

  printSection('Security');
  console.log(
    '  • Private keys are read via a hidden terminal prompt, never from argv/env.\n' +
      '  • Keys are wiped from memory immediately after signing.\n' +
      '  • Wallet client / Safe kit references are dropped and re-initialized empty.\n' +
      '  • Close the terminal after sensitive operations.\n'
  );

  printSection('License');
  console.log('  License is undecided. See README.md and LICENSE for status.\n');
}

// --------------------------------------------------------------------------
// Common helpers
// --------------------------------------------------------------------------

function getRpcUrl(argv: { rpcUrl?: string }): string {
  if (!argv.rpcUrl) {
    throw new Error('Missing --rpc-url or RPC_URL env var');
  }
  return argv.rpcUrl;
}

function getChainId(): bigint {
  const fromEnv = process.env.CHAIN_ID;
  return fromEnv ? BigInt(fromEnv) : BigInt(CHAIN_ID_MAINNET);
}

function getPoolIds(argv: { pools?: string[] }): Hex[] {
  const extras = argv.pools ?? [];
  const ids = resolveTargetPools(extras as Hex[]);
  return validatePoolIds(ids);
}

function parseOperatedPools(input?: string[]): Hex[] {
  const pools = input ?? [];
  return validatePoolIds(pools as Hex[]);
}

interface RunOperationArgv {
  wallet: string;
  dryRun: boolean;
  forceSafe: boolean;
  signerMode: SignerMode;
  rpcUrl?: string;
  txServiceUrl?: string;
}

async function runOperation(
  argv: RunOperationArgv,
  buildPlans: (publicClient: PublicClient, wallet: Address) => Promise<{
    plans: import('./operations/types.js').OperationPlan[];
    summary: string;
  }>
): Promise<void> {
  const rpcUrl = getRpcUrl(argv);
  const publicClient = createPublicClientFromUrl(rpcUrl);
  const wallet = await resolveWallet(publicClient, argv.wallet, argv.forceSafe);

  info(`Resolved wallet ${wallet.address} as ${wallet.isSafe ? 'Safe' : 'EOA'}`);

  const { plans, summary } = await buildPlans(publicClient, wallet.address);
  info(summary);
  printOperationPlans(plans);

  if (wallet.isSafe) {
    await simulateSafePlans(publicClient, wallet.address, plans);
    const { securePrompt, wipeSecret } = await import('./utils/security.js');
    let safeSignerKey = await securePrompt('Enter Safe owner private key for signing');
    let bundle = await createSafeBundle(
      rpcUrl,
      wallet.address,
      getChainId(),
      safeSignerKey,
      argv.txServiceUrl
    );
    try {
      const { safeTxHash } = await proposeSafeTransaction(bundle, wallet.address, plans);
      success(`Safe transaction proposed: ${safeTxHash}`);
      const backupPath = saveSafeProposalBackup(wallet.address, safeTxHash, plans);
      info(`Backup written to: ${backupPath}`);

    } finally {
      wipeSecret(safeSignerKey);
      // eslint-disable-next-line no-useless-assignment -- security: drop secret reference
      safeSignerKey = undefined as unknown as string;
      wipeKitReference(bundle);
      (bundle as any) = undefined;
    }
  } else {
    let walletClient: import('viem').WalletClient | undefined;
    let account: import('viem').Account | undefined;
    let cleanup: (() => void) | undefined;
    try {
      const loaded = await loadSigner(argv.signerMode, rpcUrl);
      walletClient = loaded.walletClient;
      account = loaded.account;
      cleanup = loaded.cleanup;
      for (const plan of plans) {
        await sendEoaTransaction(walletClient, account, publicClient, plan, argv.dryRun);
      }
    } finally {
      cleanup?.();
    }
  }

  warning('Sensitive operation complete. Close this terminal to clear any residual state.');
}

// --------------------------------------------------------------------------
// yargs command registration
// --------------------------------------------------------------------------

baseYargs
  .command(
    'menu',
    'Interactive menu to select an operation and fill inputs',
    () => {},
    async () => {
      const result = await runInteractiveMenu();
      const args: string[] = [result.command, ...result.args];
      if (result.options.dryRun) args.push('--dry-run');
      if (result.options.delegatee) {
        args.push('--delegatee', String(result.options.delegatee));
      }
      info(`Re-running with: yarn cli ${args.join(' ')}`);
      process.argv = [process.argv[0]!, process.argv[1]!, ...args];
      // Re-parse with the new argv.
      baseYargs.parse(args);
    }
  )
  .command(
    'help',
    'Show detailed help with command descriptions and GitHub source references',
    () => {},
    () => {
      showDetailedHelp();
      process.exit(0);
    }
  )
  .command(
    'undelegate-all <wallet>',
    'Undelegate all stake of a wallet',
    (y) => y.positional('wallet', { type: 'string', demandOption: true }),
    async (argv) => {
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) => {
        const { result } = await planUndelegateAll(publicClient, wallet);
        return result;
      });
    }
  )
  .command(
    'stake-new <wallet> <amount>',
    'Stake new ZRX',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planStakeNew(publicClient, wallet, amount)
      );
    }
  )
  .command(
    'delegate-equal <wallet> <amount> [pools...]',
    'Delegate aggregate ZRX equally across target pools',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true })
        .positional('pools', { type: 'string', array: true, default: [] }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      const pools = getPoolIds(argv as { pools?: string[] });
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planDelegateEqual(publicClient, wallet, amount, pools)
      );
    }
  )
  .command(
    'redelegate <wallet> <amount> [pools...]',
    'Undelegate all then delegate equally in one batch',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true })
        .positional('pools', { type: 'string', array: true, default: [] }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      const pools = getPoolIds(argv as { pools?: string[] });
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) => {
        const { result } = await planUndelegateAndDelegate(
          publicClient,
          wallet,
          amount,
          pools
        );
        return result;
      });
    }
  )
  .command(
    'stake-and-delegate <wallet> <amount> [pools...]',
    'Stake and delegate equally in one batch',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true })
        .positional('pools', { type: 'string', array: true, default: [] }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      const pools = getPoolIds(argv as { pools?: string[] });
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planStakeAndDelegate(publicClient, wallet, amount, pools)
      );
    }
  )
  .command(
    'unstake <wallet> <amount>',
    'Unstake undelegated ZRX (must wait an epoch after undelegating)',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planUnstake(publicClient, wallet, amount)
      );
    }
  )
  .command(
    'wrap-governance <wallet> <amount>',
    'Full legacy-stake migration to wZRX governance (undelegate + endEpoch + unstake + wrap)',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true })
        .option('delegatee', {
          type: 'string',
          description: 'Address to delegate wZRX voting power to',
          demandOption: true,
        }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      const delegatee = argv.delegatee as Address;
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planWrapGovernance(publicClient, wallet, amount, delegatee)
      );
    }
  )
  .command(
    'wrap-governance-liquid <wallet> <amount>',
    'Wrap liquid ZRX into wZRX governance (does not touch delegated stake)',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('amount', { type: 'string', demandOption: true })
        .option('delegatee', {
          type: 'string',
          description: 'Address to delegate wZRX voting power to',
          demandOption: true,
        }),
    async (argv) => {
      const amount = parseZrx(argv.amount as string);
      const delegatee = argv.delegatee as Address;
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planWrapGovernanceLiquid(publicClient, wallet, amount, delegatee)
      );
    }
  )
  .command(
    'treasury-migrate-propose <wallet>',
    'Create a ZrxTreasury proposal to migrate assets to the new governance treasury',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .option('operated-pools', {
          type: 'string',
          array: true,
          default: [] as string[],
          description: 'Optional pool ids operated by the proposer (bytes32)',
        }),
    async (argv) => {
      const operatedPools = parseOperatedPools(argv['operated-pools'] as string[]);
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient, wallet) =>
        planTreasuryMigrationProposal(publicClient, wallet, operatedPools)
      );
    }
  )
  .command(
    'treasury-migrate-execute <wallet> <proposalId>',
    'Execute a passed ZrxTreasury migration proposal',
    (y) =>
      y
        .positional('wallet', { type: 'string', demandOption: true })
        .positional('proposalId', { type: 'string', demandOption: true }),
    async (argv) => {
      const proposalId = BigInt(argv.proposalId as string);
      await runOperation(argv as unknown as RunOperationArgv, async (publicClient) =>
        planTreasuryMigrationExecution(publicClient, proposalId)
      );
    }
  )
  .command(
    'safe <subcommand> [args..]',
    'Safe multisig commands',
    (y) =>
      y
        .command(
          'pending <safe>',
          'List pending Safe transactions',
          (yy) => yy.positional('safe', { type: 'string', demandOption: true }),
          async (argv) => {
            const argvTyped = argv as unknown as RunOperationArgv & { safe: string };
            const rpcUrl = getRpcUrl(argvTyped);
            const safeAddress = argv.safe as Address;
            let bundle = await createSafeBundle(rpcUrl, safeAddress, getChainId());
            try {
              const pending = await listPendingSafeTransactions(bundle, safeAddress);
              info(`Pending transactions for ${safeAddress}:`);
              for (const tx of pending.results) {
                console.log(`  ${tx.safeTxHash} → to=${tx.to} value=${tx.value} nonce=${tx.nonce} confirmations=${tx.confirmations?.length ?? 0}/${tx.confirmationsRequired}`);
              }
            } finally {
              wipeKitReference(bundle);
      (bundle as any) = undefined;
            }
          }
        )
        .command(
          'show <safe> <safeTxHash>',
          'Show a single Safe transaction and its signatures',
          (yy) =>
            yy
              .positional('safe', { type: 'string', demandOption: true })
              .positional('safeTxHash', { type: 'string', demandOption: true }),
          async (argv) => {
            const argvTyped = argv as unknown as RunOperationArgv & { safe: string; safeTxHash: string };
            const rpcUrl = getRpcUrl(argvTyped);
            const safeAddress = argv.safe as Address;
            const safeTxHash = argv.safeTxHash as Hex;
            let bundle = await createSafeBundle(rpcUrl, safeAddress, getChainId());
            try {
              const tx = await getSafeTransaction(bundle, safeTxHash);
              info(`Safe transaction ${safeTxHash}:`);
              console.log(`  to: ${tx.to}`);
              console.log(`  value: ${tx.value}`);
              console.log(`  nonce: ${tx.nonce}`);
              console.log(`  confirmations: ${tx.confirmations?.length ?? 0}/${tx.confirmationsRequired}`);
              if (tx.confirmations && tx.confirmations.length > 0) {
                console.log('  signers:');
                for (const c of tx.confirmations) {
                  console.log(`    - ${c.owner}`);
                }
              }
            } finally {
              wipeKitReference(bundle);
      (bundle as any) = undefined;
            }
          }
        )
        .command(
          'sign <safe> <safeTxHash>',
          'Sign a pending Safe transaction',
          (yy) =>
            yy
              .positional('safe', { type: 'string', demandOption: true })
              .positional('safeTxHash', { type: 'string', demandOption: true }),
          async (argv) => {
            const argvTyped = argv as unknown as RunOperationArgv & { safe: string; safeTxHash: string };
            const rpcUrl = getRpcUrl(argvTyped);
            const safeAddress = argv.safe as Address;
            const safeTxHash = argv.safeTxHash as Hex;
            const { securePrompt, wipeSecret } = await import('./utils/security.js');
            let signerKey = await securePrompt('Enter Safe owner private key for signing');
            let bundle = await createSafeBundle(
              rpcUrl,
              safeAddress,
              getChainId(),
              signerKey,
              argvTyped.txServiceUrl
            );
            try {
              await confirmSafeTransaction(bundle, safeTxHash);
              success(`Signed Safe transaction ${safeTxHash}`);
            } finally {
              wipeSecret(signerKey);
              // eslint-disable-next-line no-useless-assignment -- security: drop secret reference
              signerKey = undefined as unknown as string;
              wipeKitReference(bundle);
      (bundle as any) = undefined;
            }
          }
        )
        .command(
          'execute <safe> <safeTxHash>',
          'Execute a fully signed Safe transaction',
          (yy) =>
            yy
              .positional('safe', { type: 'string', demandOption: true })
              .positional('safeTxHash', { type: 'string', demandOption: true }),
          async (argv) => {
            const argvTyped = argv as unknown as RunOperationArgv & { safe: string; safeTxHash: string };
            const rpcUrl = getRpcUrl(argvTyped);
            const safeAddress = argv.safe as Address;
            const safeTxHash = argv.safeTxHash as Hex;
            const { securePrompt, wipeSecret } = await import('./utils/security.js');
            let signerKey = await securePrompt('Enter executor private key');
            let bundle = await createSafeBundle(
              rpcUrl,
              safeAddress,
              getChainId(),
              signerKey,
              argvTyped.txServiceUrl
            );
            try {
              await executeSafeTransaction(bundle, safeTxHash, safeAddress);
            } finally {
              wipeSecret(signerKey);
              // eslint-disable-next-line no-useless-assignment -- security: drop secret reference
              signerKey = undefined as unknown as string;
              wipeKitReference(bundle);
      (bundle as any) = undefined;
            }
          }
        )
        .demandCommand(1, 'Run "safe pending|show|sign|execute"'),
    () => {
      // Routed to a subcommand.
    }
  )
  .demandCommand(1, 'Run with "help" for command reference')
  .strict()
  .fail((msg, err, yargs) => {
    if (err && err.message) {
      error(err.message);
      process.exit(1);
    }
    if (msg) {
      console.error(yargs.help());
      console.error(`\n${msg}\nRun with "help" for detailed command reference.`);
    }
    process.exit(1);
  })
  .parse();
