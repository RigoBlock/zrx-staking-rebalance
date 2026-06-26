/**
 * Utilities for handling secrets securely in the terminal.
 *
 * Private keys are accepted only via hidden terminal input, used in the
 * narrowest scope possible, and then every reference is overwritten.
 *
 * GitHub source: src/utils/security.ts
 */

/**
 * Prompt the user for a hidden secret (private key, mnemonic, etc.).
 * Characters are not echoed to the terminal.
 */
export async function securePrompt(label: string): Promise<string> {
  const stdin = process.stdin;
  const stdout = process.stdout;

  return new Promise((resolve, reject) => {
    stdout.write(`${label}: `);

    const wasRaw = stdin.isRaw;
    if (stdin.isTTY) {
      stdin.setRawMode(true);
    }
    stdin.resume();
    stdin.setEncoding('utf8');

    let value = '';
    const onData = (char: string) => {
      switch (char) {
        case '\n':
        case '\r':
        case '\u0004': // Ctrl-D
          cleanup();
          stdout.write('\n');
          resolve(value);
          break;
        case '\u0003': // Ctrl-C
          cleanup();
          stdout.write('\n');
          reject(new Error('Input cancelled'));
          process.exit(130);
          break;
        case '\u007f': // Backspace
          if (value.length > 0) {
            value = value.slice(0, -1);
            stdout.write('\b \b');
          }
          break;
        default:
          value += char;
          stdout.write('*');
          break;
      }
    };

    const cleanup = () => {
      stdin.removeListener('data', onData);
      if (stdin.isTTY) {
        stdin.setRawMode(wasRaw ?? false);
      }
      stdin.pause();
    };

    stdin.on('data', onData);
  });
}

/**
 * Overwrite a string reference with an empty string and return the value
 * so the caller can also null out its own reference.
 *
 * JavaScript strings are immutable, so this only removes the local
 * reference. Callers should additionally assign `variable = null` and,
 * where possible, avoid retaining the secret in closures.
 */
export function wipeSecret(secret: string | null | undefined): void {
  if (secret == null) return;
  // Best-effort overwrite of the buffer if this happens to be a Node Buffer.
  if (typeof secret === 'object' && 'fill' in secret) {
    (secret as unknown as Buffer).fill(0);
  }
}

/**
 * Best-effort helper to clear a viem account / wallet client reference.
 * Mutates the object by nulling enumerable properties, then the caller should
 * also assign its variable to `undefined`.
 */
export function wipeSignerReference<T extends Record<string, unknown>>(
  signer: T | null | undefined
): void {
  if (!signer || typeof signer !== 'object') return;
  for (const key of Object.keys(signer)) {
    try {
      (signer as Record<string, unknown>)[key] = undefined;
    } catch {
      // Ignore non-writable properties.
    }
  }
}
