/**
 * Old 0x ZrxTreasury governance contract helpers.
 *
 * The old treasury at 0x0bb1810061c2f5b2088054ee184e6c79e1591101 only moves
 * assets through passed proposals. This module encodes `propose` and `execute`
 * calls and provides read helpers for thresholds / voting power.
 *
 * GitHub source: src/contracts/treasury.ts
 */

import { encodeFunctionData, type Abi, type Address, type Hex, type PublicClient } from 'viem';
import {
  ERC20_ABI,
  MATIC_TOKEN_ADDRESS,
  NEW_ZRX_TREASURY_ADDRESS,
  OLD_ZRX_TREASURY_ADDRESS,
  POLYGON_MIGRATION_ADDRESS,
  POL_TOKEN_ADDRESS,
  WCELO_TOKEN_ADDRESS,
  ZRX_TOKEN_ADDRESS,
} from '../config/constants.js';
import { withRetry } from '../ethereum/retry.js';
import { multicallRead } from '../ethereum/multicall.js';

// --------------------------------------------------------------------------
// ABI fragments
// --------------------------------------------------------------------------

export const ZRX_TREASURY_ABI: Abi = [
  {
    inputs: [
      {
        components: [
          { internalType: 'address', name: 'target', type: 'address' },
          { internalType: 'bytes', name: 'data', type: 'bytes' },
          { internalType: 'uint256', name: 'value', type: 'uint256' },
        ],
        internalType: 'struct IZrxTreasury.ProposedAction[]',
        name: 'actions',
        type: 'tuple[]',
      },
      { internalType: 'uint256', name: 'executionEpoch', type: 'uint256' },
      { internalType: 'string', name: 'description', type: 'string' },
      { internalType: 'bytes32[]', name: 'operatedPoolIds', type: 'bytes32[]' },
    ],
    name: 'propose',
    outputs: [{ internalType: 'uint256', name: 'proposalId', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'uint256', name: 'proposalId', type: 'uint256' },
      {
        components: [
          { internalType: 'address', name: 'target', type: 'address' },
          { internalType: 'bytes', name: 'data', type: 'bytes' },
          { internalType: 'uint256', name: 'value', type: 'uint256' },
        ],
        internalType: 'struct IZrxTreasury.ProposedAction[]',
        name: 'actions',
        type: 'tuple[]',
      },
    ],
    name: 'execute',
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
  { inputs: [], name: 'proposalCount', outputs: [{ internalType: 'uint256', name: 'count', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'proposalThreshold', outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'quorumThreshold', outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'defaultPoolId', outputs: [{ internalType: 'bytes32', name: '', type: 'bytes32' }], stateMutability: 'view', type: 'function' },
  {
    inputs: [
      { internalType: 'address', name: 'account', type: 'address' },
      { internalType: 'bytes32[]', name: 'operatedPoolIds', type: 'bytes32[]' },
    ],
    name: 'getVotingPower',
    outputs: [{ internalType: 'uint256', name: 'votingPower', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
];

export const POLYGON_MIGRATION_ABI: Abi = [
  {
    inputs: [{ internalType: 'uint256', name: 'amount', type: 'uint256' }],
    name: 'migrate',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
];

// --------------------------------------------------------------------------
// ProposedAction helpers
// --------------------------------------------------------------------------

export interface ProposedAction {
  target: Address;
  data: Hex;
  value: bigint;
}

export function encodeErc20Transfer(to: Address, amount: bigint): Hex {
  return encodeFunctionData({
    abi: ERC20_ABI,
    functionName: 'transfer',
    args: [to, amount],
  });
}

export function encodeErc20Approve(spender: Address, amount: bigint): Hex {
  return encodeFunctionData({
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [spender, amount],
  });
}

export function encodeMigrateMatic(amount: bigint): Hex {
  return encodeFunctionData({
    abi: POLYGON_MIGRATION_ABI,
    functionName: 'migrate',
    args: [amount],
  });
}

export function buildTreasuryMigrationActions(
  balances: TreasuryBalances
): ProposedAction[] {
  const actions: ProposedAction[] = [];

  if (balances.zrx > 0n) {
    actions.push({
      target: ZRX_TOKEN_ADDRESS,
      data: encodeErc20Transfer(NEW_ZRX_TREASURY_ADDRESS, balances.zrx),
      value: 0n,
    });
  }

  if (balances.wCelo > 0n) {
    actions.push({
      target: WCELO_TOKEN_ADDRESS,
      data: encodeErc20Transfer(NEW_ZRX_TREASURY_ADDRESS, balances.wCelo),
      value: 0n,
    });
  }

  if (balances.matic > 0n) {
    actions.push(
      {
        target: MATIC_TOKEN_ADDRESS,
        data: encodeErc20Approve(POLYGON_MIGRATION_ADDRESS, balances.matic),
        value: 0n,
      },
      {
        target: POLYGON_MIGRATION_ADDRESS,
        data: encodeMigrateMatic(balances.matic),
        value: 0n,
      },
      {
        target: POL_TOKEN_ADDRESS,
        data: encodeErc20Transfer(NEW_ZRX_TREASURY_ADDRESS, balances.matic),
        value: 0n,
      }
    );
  }

  return actions;
}

// --------------------------------------------------------------------------
// On-chain reads
// --------------------------------------------------------------------------

export interface TreasuryBalances {
  zrx: bigint;
  wCelo: bigint;
  matic: bigint;
}

export async function readTreasuryBalances(
  publicClient: PublicClient,
  treasury: Address = OLD_ZRX_TREASURY_ADDRESS
): Promise<TreasuryBalances> {
  const [zrx, wCelo, matic] = await withRetry(() =>
    multicallRead(publicClient, [
      { address: ZRX_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf', args: [treasury] },
      { address: WCELO_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf', args: [treasury] },
      { address: MATIC_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: 'balanceOf', args: [treasury] },
    ])
  );
  return {
    zrx: zrx as bigint,
    wCelo: wCelo as bigint,
    matic: matic as bigint,
  };
}

export interface TreasuryThresholds {
  proposalThreshold: bigint;
  quorumThreshold: bigint;
  defaultPoolId: Hex;
}

export async function readTreasuryThresholds(
  publicClient: PublicClient,
  treasury: Address = OLD_ZRX_TREASURY_ADDRESS
): Promise<TreasuryThresholds> {
  const [proposalThreshold, quorumThreshold, defaultPoolId] = await withRetry(() =>
    multicallRead(publicClient, [
      { address: treasury, abi: ZRX_TREASURY_ABI, functionName: 'proposalThreshold' },
      { address: treasury, abi: ZRX_TREASURY_ABI, functionName: 'quorumThreshold' },
      { address: treasury, abi: ZRX_TREASURY_ABI, functionName: 'defaultPoolId' },
    ])
  );
  return {
    proposalThreshold: proposalThreshold as bigint,
    quorumThreshold: quorumThreshold as bigint,
    defaultPoolId: defaultPoolId as Hex,
  };
}

export async function readTreasuryVotingPower(
  publicClient: PublicClient,
  account: Address,
  operatedPoolIds: Hex[],
  treasury: Address = OLD_ZRX_TREASURY_ADDRESS
): Promise<bigint> {
  return (await withRetry(() =>
    publicClient.readContract({
      address: treasury,
      abi: ZRX_TREASURY_ABI,
      functionName: 'getVotingPower',
      args: [account, operatedPoolIds],
    })
  )) as bigint;
}

// --------------------------------------------------------------------------
// Calldata encoders
// --------------------------------------------------------------------------

export function encodeTreasuryPropose(
  actions: ProposedAction[],
  executionEpoch: bigint,
  description: string,
  operatedPoolIds: Hex[]
): Hex {
  return encodeFunctionData({
    abi: ZRX_TREASURY_ABI,
    functionName: 'propose',
    args: [
      actions.map((a) => ({ target: a.target, data: a.data, value: a.value })),
      executionEpoch,
      description,
      operatedPoolIds,
    ],
  });
}

export function encodeTreasuryExecute(
  proposalId: bigint,
  actions: ProposedAction[]
): Hex {
  return encodeFunctionData({
    abi: ZRX_TREASURY_ABI,
    functionName: 'execute',
    args: [proposalId, actions.map((a) => ({ target: a.target, data: a.data, value: a.value }))],
  });
}
