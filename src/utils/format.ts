/**
 * Terminal formatting helpers.
 *
 * GitHub source: src/utils/format.ts
 */

import chalk from 'chalk';

export const info = (msg: string) => console.log(chalk.blue('ℹ'), msg);
export const success = (msg: string) => console.log(chalk.green('✔'), msg);
export const warning = (msg: string) => console.log(chalk.yellow('⚠'), msg);
export const error = (msg: string) => console.error(chalk.red('✖'), msg);

export function printSection(title: string): void {
  console.log('\n' + chalk.bold(title));
  console.log(chalk.gray('─'.repeat(title.length)));
}

export function printTxPreview(label: string, tx: Record<string, unknown>): void {
  printSection(label);
  for (const [key, value] of Object.entries(tx)) {
    const valueStr =
      typeof value === 'bigint'
        ? value.toString()
        : Array.isArray(value)
        ? JSON.stringify(value)
        : String(value);
    console.log(`  ${chalk.gray(key)}: ${valueStr}`);
  }
}
