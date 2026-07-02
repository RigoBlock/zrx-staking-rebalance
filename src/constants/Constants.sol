// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Constants {
    // 0x protocol contracts
    address public constant STAKING_PROXY = 0xa26e80e7Dea86279c6d778D702Cc413E6CFfA777;
    address public constant ZRX_TOKEN = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address public constant ERC20_PROXY = 0x95E6F48254609A6ee006F7D493c8e5fB97094ceF;
    address public constant WZRX_TOKEN = 0xFCfaf7834F134F5146dBB3274baB9bED4bAfa917;
    address public constant TUPLE_FIXER = 0x609AbE9B2B09D1e2C2ABfE93dFFFD9f596d9A06e;

    // Treasury contracts (governance/timelock, NOT Safe wallets).
    address public constant OLD_ZRX_TREASURY = 0x0bB1810061C2f5b2088054eE184E6C79e1591101;
    address public constant NEW_ZRX_TREASURY = 0x4822cFC1e7699BdB9551BDFD3a838EE414Bc2008;

    // Safe multisigs
    // The Safe that owns the delegated stake in the legacy ZRX staking system.
    address public constant LEGACY_STAKE_SAFE_OWNER = 0x5775afA796818ADA27b09FaF5c90d101f04eF600;
    // New 0x Labs deployment Safe (from 0x Settler chain_config.json, mainnet governance.deploymentSafe).
    address public constant OX_LABS_DEPLOYMENT_SAFE = 0x8E5DE7118a596E99B0563D3022039c11927f4827;

    // Safe v1.3.0 infrastructure (mainnet).
    address public constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address public constant SAFE_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    // MultiSendCallOnly v1.3.0 — used to batch calls inside a single Safe transaction.
    address public constant SAFE_MULTISEND_CALL_ONLY = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;

    // Migration-related tokens
    address public constant POLYGON_MIGRATION = 0x29e7DF7b6A1B2b07b731457f499E1696c60E2C4e;
    address public constant POL_TOKEN = 0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6;
    address public constant WCELO_TOKEN = 0xE452E6Ea2dDeB012e20dB73bf5d3863A3Ac8d77a;
    address public constant MATIC_TOKEN = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;

    bytes32 public constant TARGET_POOL_31 = 0x0000000000000000000000000000000000000000000000000000000000000031;
    bytes32 public constant TARGET_POOL_48 = 0x0000000000000000000000000000000000000000000000000000000000000048;
    bytes32 public constant TARGET_POOL_34 = 0x0000000000000000000000000000000000000000000000000000000000000034;

    // Default actors used by scripts when the caller passes address(0).
    address public constant DEFAULT_STAKER = LEGACY_STAKE_SAFE_OWNER;
    address public constant DEFAULT_DELEGATEE = OX_LABS_DEPLOYMENT_SAFE;

    // Sentinel passed to scripts to mean "use the full available balance/amount".
    uint256 public constant USE_FULL_BALANCE = type(uint256).max;

    // Mainnet block pinned for reproducible fork tests. Update when on-chain state required by tests changes.
    uint256 public constant FORK_BLOCK_NUMBER = 25_400_000;
}
