/**
 * Human-readable decoder for Safe transaction calldata.
 *
 * Understands:
 *   - direct calls to the 0x Staking Proxy (batchExecute, stake, unstake, moveStake)
 *   - ERC20 approve
 *   - wZRX depositFor / delegate
 *
 * GitHub source: src/safe/decoder.ts
 */

import { decodeFunctionData, type Address, type Hex } from 'viem';
import {
  ERC20_ABI,
  STAKING_PROXY_ABI,
  STAKING_PROXY_ADDRESS,
  WZRX_ABI,
  WZRX_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import { getPoolLabel } from '../config/pools.js';
import { StakeStatus, type StakeInfo } from '../types.js';
import { formatZrx } from '../utils/amounts.js';

export function decodeSafeTransactionData(
  data: Hex,
  to: Address
): string[] | undefined {
  if (to.toLowerCase() === STAKING_PROXY_ADDRESS.toLowerCase()) {
    return decodeStakingCall(data);
  }
  if (to.toLowerCase() === ZRX_TOKEN_ADDRESS.toLowerCase()) {
    return decodeZrxCall(data);
  }
  if (to.toLowerCase() === WZRX_TOKEN_ADDRESS.toLowerCase()) {
    return decodeWzrxCall(data);
  }
  return undefined;
}

function decodeStakingCall(data: Hex): string[] {
  const decoded = decodeFunctionData({ abi: STAKING_PROXY_ABI, data });
  const fn = decoded.functionName;
  const args = decoded.args ?? [];

  switch (fn) {
    case 'batchExecute': {
      const calls = args[0] as Hex[];
      return calls.flatMap((call) => decodeStakingCall(call) ?? ['Unknown inner call']);
    }
    case 'stake': {
      const amount = args[0] as bigint;
      return [`Stake ${formatZrx(amount)} ZRX`];
    }
    case 'unstake': {
      const amount = args[0] as bigint;
      return [`Unstake ${formatZrx(amount)} ZRX`];
    }
    case 'moveStake': {
      const from = args[0] as StakeInfo;
      const to = args[1] as StakeInfo;
      const amount = args[2] as bigint;
      const fromLabel =
        from.status === StakeStatus.DELEGATED
          ? getPoolLabel(from.poolId)
          : 'undelegated';
      const toLabel =
        to.status === StakeStatus.DELEGATED
          ? getPoolLabel(to.poolId)
          : 'undelegated';
      return [`Move ${formatZrx(amount)} ZRX from ${fromLabel} to ${toLabel}`];
    }
    default:
      return [`Staking proxy call: ${fn}`];
  }
}

function decodeZrxCall(data: Hex): string[] {
  const decoded = decodeFunctionData({ abi: ERC20_ABI, data });
  const args = decoded.args ?? [];
  if (decoded.functionName === 'approve') {
    const [spender, amount] = args as [Address, bigint];
    return [`Approve ${spender} to spend ${formatZrx(amount)} ZRX`];
  }
  return [`ZRX call: ${decoded.functionName}`];
}

function decodeWzrxCall(data: Hex): string[] {
  const decoded = decodeFunctionData({ abi: WZRX_ABI, data });
  const args = decoded.args ?? [];
  if (decoded.functionName === 'depositFor') {
    const [account, amount] = args as [Address, bigint];
    return [`Wrap ${formatZrx(amount)} ZRX into wZRX for ${account}`];
  }
  if (decoded.functionName === 'delegate') {
    const [delegatee] = args as [Address];
    return [`Delegate wZRX voting power to ${delegatee}`];
  }
  return [`wZRX call: ${decoded.functionName}`];
}
