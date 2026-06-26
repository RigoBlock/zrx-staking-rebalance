import { createWalletClient, encodeFunctionData, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { mainnet } from 'viem/chains';
import { startAnvilFork } from '../tests/integration/anvil.js';
import { STAKING_PROXY_ADDRESS } from '../src/config/constants.js';

const TEST_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

const fork = await startAnvilFork(process.env.RPC_URL!);
const walletClient = createWalletClient({
  chain: mainnet,
  transport: http(fork.rpcUrl),
  account: privateKeyToAccount(TEST_PRIVATE_KEY as `0x${string}`),
});

const block = await fork.publicClient.getBlock();
console.log('block timestamp', block.timestamp);
const currentEpoch = await fork.publicClient.readContract({
  address: STAKING_PROXY_ADDRESS,
  abi: parseAbi(['function currentEpoch() view returns (uint256)']),
  functionName: 'currentEpoch',
});
const startTime = await fork.publicClient.readContract({
  address: STAKING_PROXY_ADDRESS,
  abi: parseAbi(['function currentEpochStartTimeInSeconds() view returns (uint256)']),
  functionName: 'currentEpochStartTimeInSeconds',
});
const epochDuration = await fork.publicClient.readContract({
  address: STAKING_PROXY_ADDRESS,
  abi: parseAbi(['function epochDurationInSeconds() view returns (uint256)']),
  functionName: 'epochDurationInSeconds',
});
console.log({ currentEpoch, startTime, epochDuration, endTime: (startTime as bigint) + (epochDuration as bigint) });

await fork.testClient.increaseTime({ seconds: Number(epochDuration) + 100 });
await fork.testClient.mine({ blocks: 1 });

const block2 = await fork.publicClient.getBlock();
console.log('block timestamp after advance', block2.timestamp);

try {
  const hash = await walletClient.sendTransaction({
    chain: mainnet,
    account: walletClient.account.address,
    to: STAKING_PROXY_ADDRESS,
    data: encodeFunctionData({
      abi: parseAbi(['function endEpoch() returns (uint256)']),
      functionName: 'endEpoch',
    }),
  });
  console.log('tx hash', hash);
  const receipt = await fork.publicClient.waitForTransactionReceipt({ hash });
  console.log('status', receipt.status);
} catch (e) {
  console.error('endEpoch failed', e);
}

await fork.stop();
