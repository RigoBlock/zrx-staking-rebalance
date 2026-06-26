/**
 * Hard-coded network and contract configuration for the ZRX rebalance CLI.
 *
 * All mainnet addresses and ABIs live here so they are easy to audit.
 * GitHub source: src/config/constants.ts
 */

import type { Abi, Address, Hex } from 'viem';

export const CHAIN_ID_MAINNET = 1;

// --------------------------------------------------------------------------
// Contract addresses
// --------------------------------------------------------------------------

/** 0x Staking Proxy (delegate target for all staking operations). */
export const STAKING_PROXY_ADDRESS: Address =
  '0xa26e80e7dea86279c6d778d702cc413e6cffa777';

/** ZRX ERC20 token. */
export const ZRX_TOKEN_ADDRESS: Address =
  '0xE41d2489571d322189246DaFA5ebDe1F4699F498';

/** 0x ERC20 Asset Proxy — the spender that must be approved to stake ZRX. */
export const ERC20_PROXY_ADDRESS: Address =
  '0x95e6f48254609a6ee006f7d493c8e5fb97094cef';

/** ZRX Vault — holds staked ZRX (used for reads and reference only). */
export const ZRX_VAULT_ADDRESS: Address =
  '0xba7f8b5fb1b19c1211c5d49550fcd149177a5eaf';

/** Wrapped ZRX token for the new governance model. */
export const WZRX_TOKEN_ADDRESS: Address =
  '0xfcfaf7834f134f5146dbb3274bab9bed4bafa917';

/** ZeroExVotes proxy used by wZRX for voting power. */
export const ZEROEX_VOTES_PROXY_ADDRESS: Address =
  '0x9c766e51b46cbc1fa4f8b6718ed4a60ac9d591fb';

/** Old 0x ZrxTreasury contract (governs migration of treasury assets). */
export const OLD_ZRX_TREASURY_ADDRESS: Address =
  '0x0bb1810061c2f5b2088054ee184e6c79e1591101';

/** New 0x governance treasury (ZeroExTreasuryGovernor). */
export const NEW_ZRX_TREASURY_ADDRESS: Address =
  '0x4822cfc1e7699bdb9551bdfd3a838ee414bc2008';

/** Polygon MATIC → POL migration proxy on Ethereum mainnet. */
export const POLYGON_MIGRATION_ADDRESS: Address =
  '0x29e7DF7b6A1B2b07b731457f499E1696c60E2C4e';

/** POL token (successor to MATIC) on Ethereum mainnet. */
export const POL_TOKEN_ADDRESS: Address =
  '0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6';

/** Wrapped CELO token held by the old treasury. */
export const WCELO_TOKEN_ADDRESS: Address =
  '0xe452e6ea2ddeb012e20db73bf5d3863a3ac8d77a';

/** MATIC token held by the old treasury. */
export const MATIC_TOKEN_ADDRESS: Address =
  '0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0';

// --------------------------------------------------------------------------
// Wallet addresses supplied by the user
// --------------------------------------------------------------------------

export const EOA_WALLET_ADDRESS: Address =
  '0xE1bdcd3B70e077D2d66ADcbe78be3941F0BF380B';

export const SAFE_WALLET_ADDRESS: Address =
  '0x5775afA796818ADA27b09FaF5c90d101f04eF600';

// --------------------------------------------------------------------------
// Target staking pools
// --------------------------------------------------------------------------

export const TARGET_POOL_31: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000031';
export const TARGET_POOL_48: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000048';
export const TARGET_POOL_34: Hex =
  '0x0000000000000000000000000000000000000000000000000000000000000034';

export const DEFAULT_TARGET_POOLS: Hex[] = [
  TARGET_POOL_31,
  TARGET_POOL_48,
  TARGET_POOL_34,
];

// --------------------------------------------------------------------------
// ABIs
// --------------------------------------------------------------------------

/** Minimal ABI for the 0x Staking Proxy (batchExecute + IStaking methods). */
export const STAKING_PROXY_ABI: Abi = [
  {
    inputs: [{ internalType: 'bytes[]', name: 'data', type: 'bytes[]' }],
    name: 'batchExecute',
    outputs: [{ internalType: 'bytes[]', name: 'batchReturnData', type: 'bytes[]' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { components: [{ internalType: 'uint8', name: 'status', type: 'uint8' }, { internalType: 'bytes32', name: 'poolId', type: 'bytes32' }], internalType: 'struct IStructs.StakeInfo', name: 'from', type: 'tuple' },
      { components: [{ internalType: 'uint8', name: 'status', type: 'uint8' }, { internalType: 'bytes32', name: 'poolId', type: 'bytes32' }], internalType: 'struct IStructs.StakeInfo', name: 'to', type: 'tuple' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' },
    ],
    name: 'moveStake',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'uint256', name: 'amount', type: 'uint256' }],
    name: 'stake',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'uint256', name: 'amount', type: 'uint256' }],
    name: 'unstake',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'endEpoch',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'currentEpoch',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'currentEpochStartTimeInSeconds',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'epochDurationInSeconds',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'staker', type: 'address' },
      { internalType: 'uint8', name: 'stakeStatus', type: 'uint8' },
    ],
    name: 'getOwnerStakeByStatus',
    outputs: [
      {
        components: [
          { internalType: 'uint64', name: 'currentEpoch', type: 'uint64' },
          { internalType: 'uint96', name: 'currentEpochBalance', type: 'uint96' },
          { internalType: 'uint96', name: 'nextEpochBalance', type: 'uint96' },
        ],
        internalType: 'struct IStructs.StoredBalance',
        name: 'balance',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'staker', type: 'address' },
      { internalType: 'bytes32', name: 'poolId', type: 'bytes32' },
    ],
    name: 'getStakeDelegatedToPoolByOwner',
    outputs: [
      {
        components: [
          { internalType: 'uint64', name: 'currentEpoch', type: 'uint64' },
          { internalType: 'uint96', name: 'currentEpochBalance', type: 'uint96' },
          { internalType: 'uint96', name: 'nextEpochBalance', type: 'uint96' },
        ],
        internalType: 'struct IStructs.StoredBalance',
        name: 'balance',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
];

/** Minimal ERC20 ABI used for ZRX approvals / balances. */
export const ERC20_ABI: Abi = [
  {
    inputs: [
      { internalType: 'address', name: 'spender', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'owner', type: 'address' },
      { internalType: 'address', name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'address', name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'to', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
];

/** Minimal ABI for the wZRX governance wrapper. */
export const WZRX_ABI: Abi = [
  {
    inputs: [
      { internalType: 'address', name: 'account', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' },
    ],
    name: 'depositFor',
    outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'address', name: 'delegatee', type: 'address' }],
    name: 'delegate',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'address', name: 'account', type: 'address' }],
    name: 'delegates',
    outputs: [{ internalType: 'address', name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ internalType: 'address', name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
];

/** TupleFixer ABI (helper to encode undelegate-all calldata). */
export const TUPLE_FIXER_ABI: Abi = [
  {
    inputs: [],
    name: 'encodeUndelegateAll',
    outputs: [
      { internalType: 'uint256', name: 'totalUndelegatedAmount', type: 'uint256' },
      { internalType: 'bytes[]', name: 'encodedCalls', type: 'bytes[]' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
];

// --------------------------------------------------------------------------
// Environment defaults
// --------------------------------------------------------------------------

export const SAFE_TX_SERVICE_MAINNET = 'https://safe-transaction-mainnet.safe.global';
