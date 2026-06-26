/**
 * Bounded async retry helper.
 *
 * Uses exponential backoff with jitter, a per-attempt maximum delay, and an
 * overall timeout. There are no infinite loops: the loop terminates after
 * `maxAttempts` or when `totalTimeoutMs` is exceeded.
 *
 * GitHub source: src/ethereum/retry.ts
 */

export interface RetryOptions {
  /** Maximum number of attempts (default: 5). */
  maxAttempts?: number;
  /** Initial delay in milliseconds (default: 250). */
  initialDelayMs?: number;
  /** Maximum delay between attempts in milliseconds (default: 30_000). */
  maxDelayMs?: number;
  /** Overall timeout in milliseconds (default: 120_000). */
  totalTimeoutMs?: number;
  /** Optional label used in error messages. */
  label?: string;
  /**
   * Return true to retry the error; return false to throw immediately.
   * Defaults to retrying network-like errors.
   */
  isRetryable?: (err: unknown) => boolean;
}

const defaultIsRetryable = (err: unknown): boolean => {
  if (!(err instanceof Error)) return false;
  const message = err.message.toLowerCase();
  return (
    message.includes('timeout') ||
    message.includes('network') ||
    message.includes('econnrefused') ||
    message.includes('disconnected') ||
    message.includes('rate limit') ||
    message.includes('too many requests') ||
    message.includes('invalid json rpc') ||
    message.includes('fetch failed') ||
    message.includes('request failed')
  );
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Execute `fn` with bounded retries.
 */
export async function withRetry<T>(
  fn: (attempt: number) => Promise<T> | T,
  options: RetryOptions = {}
): Promise<T> {
  const {
    maxAttempts = 5,
    initialDelayMs = 250,
    maxDelayMs = 30_000,
    totalTimeoutMs = 120_000,
    label = 'operation',
    isRetryable = defaultIsRetryable,
  } = options;

  const deadline = Date.now() + totalTimeoutMs;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn(attempt);
    } catch (err) {
      const canRetry = isRetryable(err);
      const isLast = attempt === maxAttempts || Date.now() >= deadline;

      if (!canRetry || isLast) {
        const prefix = label ? `${label} failed` : 'Operation failed';
        throw new Error(`${prefix} after ${attempt} attempt(s): ${err instanceof Error ? err.message : String(err)}`, { cause: err });
      }

      const exponential = initialDelayMs * 2 ** (attempt - 1);
      const capped = Math.min(exponential, maxDelayMs);
      const jitter = Math.random() * capped * 0.5;
      const delay = Math.min(capped + jitter, maxDelayMs, deadline - Date.now());

      if (delay > 0) {
        await sleep(delay);
      }
    }
  }

  // Unreachable because the loop always returns or throws, but TypeScript
  // needs a fallback.
  throw new Error(`${label} failed: exhausted all retry attempts`);
}
