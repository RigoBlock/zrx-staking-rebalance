#!/usr/bin/env bash
# Safe-related constants used by the Safe wrappers.

# Safe Transaction Service (mainnet only).
readonly SAFE_TX_SERVICE_URL="https://api.safe.global/tx-service/eth/api"

# Origin tag sent to the Safe Transaction Service.
readonly SAFE_ORIGIN="zrx-staking-rebalance"

# Safe multisigs
readonly LEGACY_STAKE_SAFE_OWNER="0x5775afA796818ADA27b09FaF5c90d101f04eF600"
readonly OX_LABS_DEPLOYMENT_SAFE="0x8E5DE7118a596E99B0563D3022039c11927f4827"
