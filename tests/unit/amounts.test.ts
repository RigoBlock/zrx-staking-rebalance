import { describe, expect, it } from 'vitest';
import {
  formatAllocations,
  formatZrx,
  parseZrx,
  splitEqually,
  validateSplit,
} from '../../src/utils/amounts.js';

describe('amounts', () => {
  describe('splitEqually', () => {
    it('splits evenly when divisible', () => {
      expect(splitEqually(300n, 3)).toEqual([100n, 100n, 100n]);
    });

    it('distributes remainder 1 wei at a time', () => {
      expect(splitEqually(10n, 3)).toEqual([4n, 3n, 3n]);
    });

    it('handles single bucket', () => {
      expect(splitEqually(12345n, 1)).toEqual([12345n]);
    });

    it('rejects zero count', () => {
      expect(() => splitEqually(100n, 0)).toThrow('count must be positive');
    });
  });

  describe('validateSplit', () => {
    it('passes for valid split', () => {
      expect(() => validateSplit([4n, 3n, 3n], 10n)).not.toThrow();
    });

    it('throws for invalid split', () => {
      expect(() => validateSplit([4n, 3n, 2n], 10n)).toThrow(
        'Split validation failed'
      );
    });
  });

  describe('parseZrx / formatZrx', () => {
    it('parses integer amounts', () => {
      expect(parseZrx('1')).toBe(10n ** 18n);
    });

    it('parses decimal amounts', () => {
      expect(parseZrx('0.5')).toBe(5n * 10n ** 17n);
    });

    it('rejects invalid input', () => {
      expect(() => parseZrx('abc')).toThrow('Invalid ZRX amount');
    });

    it('formats wei back to decimal', () => {
      expect(formatZrx(10n ** 18n)).toBe('1');
      expect(formatZrx(5n * 10n ** 17n)).toBe('0.5');
    });
  });

  describe('formatAllocations', () => {
    it('renders a table', () => {
      const out = formatAllocations(
        ['0x0000000000000000000000000000000000000000000000000000000000000031'],
        [10n ** 18n]
      );
      expect(out).toContain('0031');
      expect(out).toContain('1 ZRX');
    });
  });
});
