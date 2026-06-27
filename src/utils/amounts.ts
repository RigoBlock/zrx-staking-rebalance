/**
 * Amount splitting and formatting helpers.
 *
 * GitHub source: src/utils/amounts.ts
 */

import type { Hex } from 'viem';

/** Split an aggregate amount as evenly as possible across `count` buckets. */
export function splitEqually(amount: bigint, count: number): bigint[] {
  if (count <= 0) throw new Error('count must be positive');
  if (amount < 0n) throw new Error('amount must be non-negative');

  const base = amount / BigInt(count);
  const remainder = amount - base * BigInt(count);
  const parts: bigint[] = [];
  for (let i = 0; i < count; i++) {
    parts.push(base + (BigInt(i) < remainder ? 1n : 0n));
  }
  return parts;
}

/** Validate that the sum of parts equals the original amount. */
export function validateSplit(parts: bigint[], total: bigint): void {
  const sum = parts.reduce((a, b) => a + b, 0n);
  if (sum !== total) {
    throw new Error(
      `Split validation failed: ${sum.toString()} !== ${total.toString()}`
    );
  }
}

/** Format wei as a human-readable ZRX string (18 decimals). */
export function formatZrx(wei: bigint): string {
  const unit = 10n ** 18n;
  const whole = wei / unit;
  const fraction = wei % unit;
  const fractionStr = fraction.toString().padStart(18, '0').replace(/0+$/, '');
  return fractionStr.length > 0 ? `${whole}.${fractionStr}` : `${whole}`;
}

/** Parse a decimal or integer ZRX string into wei. */
export function parseZrx(input: string): bigint {
  const clean = input.trim();
  if (!/^\d+(\.\d+)?$/.test(clean)) {
    throw new Error(`Invalid ZRX amount: ${input}`);
  }
  const [whole, fraction = ''] = clean.split('.');
  const padded = (fraction + '000000000000000000').slice(0, 18);
  return BigInt(whole) * 10n ** 18n + BigInt(padded);
}

/**
 * Split a total amount proportionally to a set of weights.
 * The remainder (if any) is added to the last part so the returned parts
 * always sum to `total`.
 */
export function splitByWeights(total: bigint, weights: bigint[]): bigint[] {
  if (weights.length === 0) throw new Error('weights must not be empty');
  if (total < 0n) throw new Error('total must be non-negative');

  const totalWeight = weights.reduce((a, b) => a + b, 0n);
  if (totalWeight === 0n) throw new Error('total weight must be greater than 0');

  let distributed = 0n;
  const parts = weights.map((weight, i) => {
    if (i === weights.length - 1) {
      return total - distributed;
    }
    const part = (total * weight) / totalWeight;
    distributed += part;
    return part;
  });
  return parts;
}

/** Build a labeled allocation table for terminal output. */
export function formatAllocations(
  poolIds: Hex[],
  amounts: bigint[]
): string {
  return poolIds
    .map((id, i) => `  ${id}: ${formatZrx(amounts[i])} ZRX`)
    .join('\n');
}
