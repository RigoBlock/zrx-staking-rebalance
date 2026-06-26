import { describe, expect, it } from 'vitest';
import { withRetry } from '../../src/ethereum/retry.js';

describe('withRetry', () => {
  it('returns the result on the first attempt', async () => {
    const result = await withRetry(() => 'ok');
    expect(result).toBe('ok');
  });

  it('retries on retryable errors', async () => {
    let attempts = 0;
    const result = await withRetry(
      () => {
        attempts++;
        if (attempts < 3) throw new Error('network timeout');
        return 'ok';
      },
      { initialDelayMs: 1 }
    );
    expect(result).toBe('ok');
    expect(attempts).toBe(3);
  });

  it('throws after exhausting attempts', async () => {
    let attempts = 0;
    await expect(
      withRetry(
        () => {
          attempts++;
          throw new Error('timeout');
        },
        { maxAttempts: 2, initialDelayMs: 1 }
      )
    ).rejects.toThrow(/failed after 2 attempt/);
    expect(attempts).toBe(2);
  });

  it('does not retry non-retryable errors', async () => {
    let attempts = 0;
    await expect(
      withRetry(
        () => {
          attempts++;
          throw new Error('bad input');
        },
        { initialDelayMs: 1 }
      )
    ).rejects.toThrow(/bad input/);
    expect(attempts).toBe(1);
  });
});
