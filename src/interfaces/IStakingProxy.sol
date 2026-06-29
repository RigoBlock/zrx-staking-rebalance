// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakingProxy {
    struct StakeInfo {
        uint8 status;
        bytes32 poolId;
    }

    struct StoredBalance {
        uint64 currentEpoch;
        uint96 currentEpochBalance;
        uint96 nextEpochBalance;
    }

    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function moveStake(StakeInfo calldata from, StakeInfo calldata to, uint256 amount) external;
    function batchExecute(bytes[] calldata data) external;
    function endEpoch() external returns (uint256);

    function getOwnerStakeByStatus(address staker, uint8 status) external view returns (StoredBalance memory);
    function getStakeDelegatedToPoolByOwner(address staker, bytes32 poolId)
        external
        view
        returns (StoredBalance memory);
    function currentEpoch() external view returns (uint256);
    function currentEpochStartTimeInSeconds() external view returns (uint256);
    function epochDurationInSeconds() external view returns (uint256);
}
