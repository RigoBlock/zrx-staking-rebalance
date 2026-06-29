// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IZrxTreasury {
    struct ProposedAction {
        address target;
        bytes data;
        uint256 value;
    }

    function propose(
        ProposedAction[] calldata actions,
        uint256 executionEpoch,
        string calldata description,
        bytes32[] calldata operatedPoolIds
    ) external returns (uint256 proposalId);

    function execute(uint256 proposalId, ProposedAction[] calldata actions) external payable;

    function proposalCount() external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function quorumThreshold() external view returns (uint256);
    function defaultPoolId() external view returns (bytes32);
    function getVotingPower(address account, bytes32[] calldata operatedPoolIds)
        external
        view
        returns (uint256);
}
