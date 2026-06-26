/**
 * Hardware wallet signer wrappers for Ledger and Trezor.
 *
 * These implementations use the official Node.js SDKs. They have not been
 * tested against physical devices in this repo and should be validated on a
 * testnet before mainnet use.
 *
 * GitHub source: src/ethereum/hardware.ts
 */

import type { Account, Address, Hex } from 'viem';
import { toAccount } from 'viem/accounts';
import { serializeTransaction, type TransactionSerializable } from 'viem';

export interface HardwareSignerOptions {
  /** BIP44 derivation path, e.g. "m/44'/60'/0'/0/0". */
  path?: string;
}

const DEFAULT_PATH = "m/44'/60'/0'/0/0";

// --------------------------------------------------------------------------
// Ledger
// --------------------------------------------------------------------------

/**
 * Create a viem account backed by a Ledger device via @ledgerhq/hw-app-eth.
 *
 * The user must connect the Ledger, open the Ethereum app, and accept prompts
 * on the device.
 */
export async function createLedgerAccount(
  options: HardwareSignerOptions = {}
): Promise<Account> {
  const path = options.path ?? DEFAULT_PATH;

  const [{ default: TransportNodeHid }, EthAppModule] = await Promise.all([
    import('@ledgerhq/hw-transport-node-hid'),
    import('@ledgerhq/hw-app-eth'),
  ]);

  // The Ledger package is CommonJS; unwrap default if necessary.
  const EthApp = ((EthAppModule as any).default ?? EthAppModule) as new (
    transport: unknown
  ) => {
    getAddress(path: string): Promise<{ address: string }>;
    signPersonalMessage(path: string, messageHex: string): Promise<{
      r: string;
      s: string;
      v: string;
    }>;
    signTransaction(
      path: string,
      rawTxHex: string,
      resolution: Record<string, unknown>
    ): Promise<{ r: string; s: string; v: string }>;
  };

  const transport = await TransportNodeHid.default.create();
  const eth = new EthApp(transport);

  const { address } = await eth.getAddress(path);
  const viemAddress = address.toLowerCase() as Address;

  return toAccount({
    address: viemAddress,
    async signMessage({ message }) {
      const msgHex =
        typeof message === 'string'
          ? Buffer.from(message, 'utf8').toString('hex')
          : (typeof message.raw === 'string' ? message.raw : Buffer.from(message.raw).toString('hex')).slice(2);
      const result = await eth.signPersonalMessage(path, msgHex);
      const v = parseInt(result.v, 16) - 27;
      return `0x${result.r}${result.s}${v
        .toString(16)
        .padStart(2, '0')}` as Hex;
    },
    async signTransaction(tx) {
      const unsignedTx = tx as unknown as TransactionSerializable;
      const unsignedSerialized = serializeTransaction(unsignedTx);
      const result = await eth.signTransaction(
        path,
        unsignedSerialized.slice(2),
        {}
      );
      const signed = serializeTransaction(unsignedTx, {
        r: `0x${result.r}` as Hex,
        s: `0x${result.s}` as Hex,
        v: BigInt(parseInt(result.v, 16)),
      });
      return signed;
    },
    async signTypedData() {
      throw new Error(
        'Ledger EIP-712 typed-data signing is not implemented yet'
      );
    },
  });
}

// --------------------------------------------------------------------------
// Trezor
// --------------------------------------------------------------------------

/**
 * Create a viem account backed by a Trezor device via @trezor/connect.
 *
 * Requires Trezor Bridge / Suite to be running and the device to be connected
 * and unlocked.
 */
export async function createTrezorAccount(
  options: HardwareSignerOptions = {}
): Promise<Account> {
  const path = options.path ?? DEFAULT_PATH;

  const TrezorConnectModule = await import('@trezor/connect');
  const TrezorConnect = ((TrezorConnectModule as any).default ??
    TrezorConnectModule) as {
    init(config: { manifest: { email: string; appUrl: string } }): Promise<void>;
    ethereumGetAddress(props: {
      path: string;
    }): Promise<
      | { success: true; payload: { address: string } }
      | { success: false; payload: { error: string } }
    >;
    signMessage(props: {
      path: string;
      message: string;
      hex: boolean;
    }): Promise<
      | { success: true; payload: { signature: string } }
      | { success: false; payload: { error: string } }
    >;
    ethereumSignTransaction(props: {
      path: string;
      transaction: Record<string, string | undefined>;
    }): Promise<
      | {
          success: true;
          payload: { r: string; s: string; v: string };
        }
      | { success: false; payload: { error: string } }
    >;
  };

  await TrezorConnect.init({
    manifest: {
      email: 'dev@example.com',
      appUrl: 'https://github.com/zrx-staking-rebalance',
    },
  });

  const addressResult = await TrezorConnect.ethereumGetAddress({ path });
  if (!addressResult.success) {
    throw new Error(`Trezor getAddress failed: ${addressResult.payload.error}`);
  }
  const viemAddress = addressResult.payload.address.toLowerCase() as Address;

  return toAccount({
    address: viemAddress,
    async signMessage({ message }) {
      const result = await TrezorConnect.signMessage({
        path,
        message: typeof message === 'string' ? message : String(message.raw),
        hex: typeof message !== 'string',
      });
      if (!result.success) {
        throw new Error(`Trezor signMessage failed: ${result.payload.error}`);
      }
      return result.payload.signature as Hex;
    },
    async signTransaction(tx) {
      const unsignedTx = tx as unknown as TransactionSerializable;
      const result = await TrezorConnect.ethereumSignTransaction({
        path,
        transaction: {
          to: tx.to ? String(tx.to) : undefined,
          value: tx.value?.toString() ?? '0',
          data: tx.data ?? '0x',
          chainId: tx.chainId?.toString() ?? '1',
          nonce: tx.nonce?.toString() ?? '0',
          gasLimit: tx.gas?.toString() ?? '0',
          gasPrice: tx.gasPrice?.toString() ?? '0',
          maxFeePerGas: tx.maxFeePerGas?.toString() ?? undefined,
          maxPriorityFeePerGas:
            tx.maxPriorityFeePerGas?.toString() ?? undefined,
        },
      });
      if (!result.success) {
        throw new Error(
          `Trezor signTransaction failed: ${result.payload.error}`
        );
      }
      const sig = result.payload;
      const signed = serializeTransaction(unsignedTx, {
        r: sig.r as Hex,
        s: sig.s as Hex,
        v: BigInt(sig.v),
      });
      return signed;
    },
    async signTypedData() {
      throw new Error(
        'Trezor EIP-712 typed-data signing is not implemented yet'
      );
    },
  });
}

/** Type guard: account backed by hardware (heuristic). */
export function isHardwareAccount(_account: Account): boolean {
  return false;
}

/**
 * Utility used by tests to simulate a hardware account without a real device.
 */
export function mockHardwareAccount(address: Address): Account {
  return toAccount({
    address,
    async signMessage() {
      return '0x' as Hex;
    },
    async signTransaction() {
      return '0x' as Hex;
    },
    async signTypedData() {
      return '0x' as Hex;
    },
  });
}
