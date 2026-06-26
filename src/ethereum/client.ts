/**
 * Viem public/wallet client factory.
 *
 * GitHub source: src/ethereum/client.ts
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  type Account,
  type Address,
  type Chain,
  type Hex,
  type PublicClient,
  type WalletClient,
} from 'viem';
import { mainnet } from 'viem/chains';

const RPC_RETRY_COUNT = 5;
const RPC_RETRY_DELAY_MS = 250;

export function getChain(chainId: number): Chain {
  if (chainId === 1) return mainnet;
  throw new Error(`Unsupported chain id: ${chainId}`);
}

export function createPublicClientFromUrl(rpcUrl: string): PublicClient {
  return createPublicClient({
    chain: mainnet,
    transport: http(rpcUrl, {
      timeout: 60_000,
      retryCount: RPC_RETRY_COUNT,
      retryDelay: RPC_RETRY_DELAY_MS,
    }),
  }) as PublicClient;
}

export function createWalletClientForAccount(
  rpcUrl: string,
  account: Account
): WalletClient {
  return createWalletClient({
    chain: mainnet,
    transport: http(rpcUrl, {
      timeout: 60_000,
      retryCount: RPC_RETRY_COUNT,
      retryDelay: RPC_RETRY_DELAY_MS,
    }),
    account,
  }) as WalletClient;
}

/** Wait for a transaction receipt, returning its status. */
export async function waitForReceipt(
  publicClient: PublicClient,
  hash: Hex,
  confirmations = 1
) {
  return publicClient.waitForTransactionReceipt({ hash, confirmations });
}

/** Resolve an address / ENS name. For now only addresses are accepted. */
export function resolveAddress(input: string): Address {
  if (!/^0x[a-fA-F0-9]{40}$/.test(input)) {
    throw new Error(`Invalid Ethereum address: ${input}`);
  }
  return input.toLowerCase() as Address;
}
