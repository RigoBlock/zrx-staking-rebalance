/**
 * Anvil fork helper for integration tests.
 *
 * GitHub source: tests/integration/anvil.ts
 */

import { type ChildProcess, spawn } from 'node:child_process';
import { createPublicClient, createTestClient, http, type PublicClient, type TestClient } from 'viem';
import { mainnet } from 'viem/chains';

export interface ForkInstance {
  rpcUrl: string;
  publicClient: PublicClient;
  testClient: TestClient;
  stop: () => Promise<void>;
}

export async function startAnvilFork(
  forkUrl: string,
  blockNumber?: number
): Promise<ForkInstance> {
  const port = 8545 + Math.floor(Math.random() * 1000);
  const rpcUrl = `http://127.0.0.1:${port}`;

  const args = [
    '--fork-url',
    forkUrl,
    '--port',
    String(port),
    '--no-rate-limit',
    ...(blockNumber ? ['--fork-block-number', String(blockNumber)] : []),
  ];

  const proc: ChildProcess = spawn('anvil', args, {
    stdio: 'ignore',
    detached: true,
  });

  // Wait for RPC to become available.
  const publicClient = createPublicClient({
    chain: mainnet,
    transport: http(rpcUrl),
  });

  for (let i = 0; i < 60; i++) {
    try {
      await publicClient.getChainId();
      break;
    } catch {
      await new Promise((r) => setTimeout(r, 500));
    }
  }

  const testClient = createTestClient({
    chain: mainnet,
    mode: 'anvil',
    transport: http(rpcUrl),
  });

  return {
    rpcUrl,
    publicClient,
    testClient,
    stop: () => {
      return new Promise<void>((resolve) => {
        if (proc.pid) {
          try {
            process.kill(-proc.pid);
          } catch {
            // ignore
          }
        }
        proc.on('exit', () => resolve());
        setTimeout(() => resolve(), 2000);
      });
    },
  };
}
