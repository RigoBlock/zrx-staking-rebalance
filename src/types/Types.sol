// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum RedelegateMode {
    UndelegateAll,
    RedelegateAll,
    RedelegateAmount
}

enum WrapGovernanceMode {
    Unstake,
    Full,
    Liquid,
    ExcludePools
}

enum TreasuryMode {
    Propose,
    Execute
}

struct Delegation {
    bytes32 poolId;
    uint256 amount;
}

struct WrapState {
    uint256 wzrxBefore;
    address delegateeBefore;
}
