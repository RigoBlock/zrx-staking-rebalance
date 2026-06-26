/**
 * Safe Protocol Kit and API Kit initializers.
 *
 * The protocol-kit caches the signer internally. After sensitive operations
 * the caller should drop the kit reference and, if possible, re-initialize
 * with an empty signer.
 *
 * GitHub source: src/safe/kit.ts
 */

import SafeModule from '@safe-global/protocol-kit';
import SafeApiKitModule from '@safe-global/api-kit';
import type { Address } from 'viem';
import { SAFE_TX_SERVICE_MAINNET } from '../config/constants.js';
import { warning } from '../utils/format.js';

// The Safe packages are CommonJS with a default class export. Node ESM
// interop sometimes surfaces the class via .default; unwrap it here so the
// code works in both typecheck and runtime environments.
const Safe = ((SafeModule as any).default ?? SafeModule) as {
  init(config: unknown): Promise<SafeInstance>;
};
const SafeApiKit = ((SafeApiKitModule as any).default ?? SafeApiKitModule) as {
  new (config: { chainId: bigint; txServiceUrl?: string }): SafeApiInstance;
};

type SafeInstance = any;
type SafeApiInstance = any;

export interface SafeKitBundle {
  protocolKit: SafeInstance;
  apiKit: SafeApiInstance;
}

export async function initSafeProtocolKit(
  rpcUrl: string,
  safeAddress: Address,
  signer?: string
): Promise<SafeInstance> {
  return Safe.init({
    provider: rpcUrl,
    signer,
    safeAddress,
  });
}

export function initSafeApiKit(
  chainId: bigint,
  txServiceUrl?: string
): SafeApiInstance {
  return new SafeApiKit({
    chainId,
    txServiceUrl: txServiceUrl ?? SAFE_TX_SERVICE_MAINNET,
  });
}

export async function initSafeKitBundle(
  rpcUrl: string,
  safeAddress: Address,
  chainId: bigint,
  signer?: string,
  txServiceUrl?: string
): Promise<SafeKitBundle> {
  const [protocolKit, apiKit] = await Promise.all([
    initSafeProtocolKit(rpcUrl, safeAddress, signer),
    Promise.resolve(initSafeApiKit(chainId, txServiceUrl)),
  ]);
  const bundle = { protocolKit, apiKit };
  await checkSafeVersion(bundle);
  return bundle;
}

/** Best-effort wipe of a kit reference. The caller must also drop its variable. */
export function wipeKitReference(kit: SafeKitBundle | undefined): void {
  if (!kit || typeof kit !== 'object') return;
  // The protocol-kit holds the signer in closures. Dropping every reference
  // is the only practical mitigation in JavaScript.
  for (const key of Object.keys(kit)) {
    try {
      (kit as unknown as Record<string, unknown>)[key] = undefined;
    } catch {
      // Ignore non-writable properties.
    }
  }
}

/** Check the Safe singleton version and warn if it is outdated. */
export async function checkSafeVersion(bundle: SafeKitBundle): Promise<string> {
  const version = bundle.protocolKit.getContractVersion() as string;
  if (version !== '1.4.1' && version !== '1.5.0') {
    warning(
      `Detected Safe version ${version}. The current Safe LTS is 1.4.1/1.5.x. ` +
        'Consider upgrading the Safe singleton. Older versions (including 1.1.1) ' +
        'have known setup-time delegatecall issues.'
    );
  }
  return version;
}
