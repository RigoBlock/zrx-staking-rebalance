/**
 * Viem multicall wrapper with serial fallback.
 *
 * Batches on-chain reads to reduce RPC round-trips. If the RPC does not support
 * multicall (or the call reverts with a non-allowlist error), the helper falls
 * back to reading contracts one by one.
 *
 * GitHub source: src/ethereum/multicall.ts
 */

import type { Abi, Address, PublicClient } from 'viem';

export interface MulticallContract<TAbi extends Abi | readonly unknown[]> {
  address: Address;
  abi: TAbi;
  functionName: string;
  args?: unknown[];
}

type MulticallResult<T> =
  | { status: 'success'; result: T }
  | { status: 'failure'; error: Error };

const MULTICALL_UNSUPPORTED_PATTERNS = [
  'multicall',
  'aggregate',
  'batch requests',
  'method not found',
  'method not supported',
];

function isMulticallUnsupported(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const message = err.message.toLowerCase();
  return MULTICALL_UNSUPPORTED_PATTERNS.some((pattern) => message.includes(pattern));
}

/**
 * Execute a batch of read calls. Returns results in the same order as `contracts`.
 *
 * Throws on the first failed call. Falls back to serial reads if multicall is
 * unavailable.
 */
export async function multicallRead<TAbi extends Abi | readonly unknown[], TResult = unknown>(
  publicClient: PublicClient,
  contracts: MulticallContract<TAbi>[]
): Promise<TResult[]> {
  if (contracts.length === 0) return [];

  try {
    const results = (await publicClient.multicall({
      contracts: contracts as unknown as {
        address: Address;
        abi: Abi;
        functionName: string;
        args?: unknown[];
      }[],
    })) as MulticallResult<TResult>[];

    return results.map((r, i) => {
      if (r.status === 'failure') {
        throw new Error(
          `Multicall read failed for ${contracts[i].functionName}@${contracts[i].address}: ${r.error.message}`,
          { cause: r.error }
        );
      }
      return r.result;
    });
  } catch (err) {
    if (!isMulticallUnsupported(err)) {
      throw err;
    }
  }

  // Fallback: read contracts sequentially.
  const serial: TResult[] = [];
  for (const c of contracts) {
    const result = (await publicClient.readContract({
      address: c.address,
      abi: c.abi as Abi,
      functionName: c.functionName,
      args: c.args,
    })) as TResult;
    serial.push(result);
  }
  return serial;
}
