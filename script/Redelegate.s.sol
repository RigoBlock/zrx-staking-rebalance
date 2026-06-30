// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {LibScript} from "../src/libraries/LibScript.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

contract Redelegate is Script {
    uint256 internal constant MAX_POOL_ID = 100;

    enum Mode {
        UndelegateAll,
        RedelegateAll,
        RedelegateAmount
    }

    function generatePlan(
        string calldata modeName,
        address staker,
        uint256 targetAmount,
        bytes32[] calldata targetPoolIds
    ) external view returns (LibScript.PlanStep[] memory) {
        Mode mode = parseMode(modeName);
        bytes[] memory calls = _buildCalls(mode, staker, targetAmount, targetPoolIds);
        LibScript.PlanStep[] memory steps = _buildPlanStep(calls);
        LibScript.emitPlanJson(steps);
        return steps;
    }

    function run(string calldata modeName, address staker, uint256 targetAmount, bytes32[] calldata targetPoolIds)
        external
    {
        Mode mode = parseMode(modeName);

        bytes[] memory calls = _buildCalls(mode, staker, targetAmount, targetPoolIds);

        if (calls.length == 0) {
            return;
        }

        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(calls);
        vm.stopBroadcast();

        _verify(mode, staker, targetAmount, targetPoolIds, delegations, totalDelegated);
    }

    function _buildPlanStep(bytes[] memory calls) internal pure returns (LibScript.PlanStep[] memory steps) {
        if (calls.length == 0) {
            return new LibScript.PlanStep[](0);
        }
        steps = new LibScript.PlanStep[](1);
        steps[0] = LibScript.PlanStep({
            to: Constants.STAKING_PROXY,
            value: 0,
            data: abi.encodeWithSelector(IStakingProxy.batchExecute.selector, calls),
            description: "Redelegate"
        });
    }

    function _buildCalls(Mode mode, address staker, uint256 targetAmount, bytes32[] calldata targetPoolIds)
        internal
        view
        returns (bytes[] memory calls)
    {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);

        require(totalDelegated > 0, "no delegated stake");

        if (mode == Mode.UndelegateAll) {
            calls = buildUndelegateCalls(delegations);
        } else if (mode == Mode.RedelegateAll) {
            require(targetPoolIds.length > 0, "no target pools");
            calls = buildRebalanceCalls(delegations, targetPoolIds, totalDelegated);
        } else {
            require(targetPoolIds.length > 0, "no target pools");
            calls = buildRedelegateAmountCalls(delegations, targetPoolIds, targetAmount);
        }
    }

    function _verify(
        Mode mode,
        address staker,
        uint256 targetAmount,
        bytes32[] calldata targetPoolIds,
        LibStaking.Delegation[] memory beforeDelegations,
        uint256 totalDelegatedBefore
    ) internal view {
        if (mode == Mode.UndelegateAll) {
            // Every previously active delegation must be scheduled for removal.
            for (uint256 i = 0; i < beforeDelegations.length; i++) {
                uint256 next_ = IStakingProxy(Constants.STAKING_PROXY)
                    .getStakeDelegatedToPoolByOwner(staker, beforeDelegations[i].poolId).nextEpochBalance;
                require(next_ == 0, "Redelegate: undelegate-all left scheduled stake");
            }
            return;
        }

        // For redelegate modes, no stake may remain scheduled outside the target pools.
        for (uint256 i = 1; i <= MAX_POOL_ID; i++) {
            bytes32 poolId = bytes32(i);
            uint256 next_ =
                IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, poolId).nextEpochBalance;
            if (next_ > 0 && !_isTarget(poolId, targetPoolIds)) {
                revert("Redelegate: non-target pool has scheduled stake");
            }
        }

        if (mode == Mode.RedelegateAll) {
            uint256 expectedTotal = totalDelegatedBefore;
            uint256[] memory parts = LibStaking.splitEqually(expectedTotal, targetPoolIds.length);
            uint256 scheduledTotal = 0;
            for (uint256 i = 0; i < targetPoolIds.length; i++) {
                uint256 next_ = IStakingProxy(Constants.STAKING_PROXY)
                    .getStakeDelegatedToPoolByOwner(staker, targetPoolIds[i]).nextEpochBalance;
                require(next_ == parts[i], "Redelegate: redelegate-all pool amount mismatch");
                scheduledTotal += next_;
            }
            require(scheduledTotal == expectedTotal, "Redelegate: redelegate-all total mismatch");
        } else {
            // RedelegateAmount
            uint256 expectedTotal = targetAmount;
            uint256 scheduledTotal = 0;
            for (uint256 i = 0; i < targetPoolIds.length; i++) {
                scheduledTotal += IStakingProxy(Constants.STAKING_PROXY)
                    .getStakeDelegatedToPoolByOwner(staker, targetPoolIds[i]).nextEpochBalance;
            }
            require(scheduledTotal == expectedTotal, "Redelegate: redelegate-amount total mismatch");
        }
    }

    function parseMode(string calldata modeName) internal pure returns (Mode) {
        if (keccak256(bytes(modeName)) == keccak256(bytes("undelegate-all"))) return Mode.UndelegateAll;
        if (keccak256(bytes(modeName)) == keccak256(bytes("redelegate-all"))) return Mode.RedelegateAll;
        if (keccak256(bytes(modeName)) == keccak256(bytes("redelegate-amount"))) return Mode.RedelegateAmount;
        revert("unknown mode");
    }

    function buildUndelegateCalls(LibStaking.Delegation[] memory delegations)
        internal
        pure
        returns (bytes[] memory calls)
    {
        calls = new bytes[](delegations.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            calls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }
    }

    function buildRebalanceCalls(
        LibStaking.Delegation[] memory delegations,
        bytes32[] calldata targetPoolIds,
        uint256 targetTotal
    ) internal pure returns (bytes[] memory calls) {
        calls = new bytes[](delegations.length + targetPoolIds.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            calls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }
        uint256[] memory parts = LibStaking.splitEqually(targetTotal, targetPoolIds.length);
        for (uint256 i = 0; i < targetPoolIds.length; i++) {
            calls[delegations.length + i] = LibStaking.encodeDelegate(targetPoolIds[i], parts[i]);
        }
    }

    function buildRedelegateAmountCalls(
        LibStaking.Delegation[] memory delegations,
        bytes32[] calldata targetPoolIds,
        uint256 targetAmount
    ) internal pure returns (bytes[] memory calls) {
        uint256 currentTarget = 0;
        uint256 nonTargetTotal = 0;

        for (uint256 i = 0; i < delegations.length; i++) {
            if (isTarget(delegations[i].poolId, targetPoolIds)) {
                currentTarget += delegations[i].amount;
            } else {
                nonTargetTotal += delegations[i].amount;
            }
        }

        if (targetAmount == currentTarget) {
            return new bytes[](0);
        }

        if (targetAmount > currentTarget) {
            uint256 surplus = targetAmount - currentTarget;
            require(surplus <= nonTargetTotal, "insufficient non-target stake");

            uint256 sourceCount = 0;
            for (uint256 i = 0; i < delegations.length; i++) {
                if (!isTarget(delegations[i].poolId, targetPoolIds)) sourceCount++;
            }

            LibStaking.Delegation[] memory sources = new LibStaking.Delegation[](sourceCount);
            uint256 idx = 0;
            uint256[] memory weights = new uint256[](sourceCount);
            for (uint256 i = 0; i < delegations.length; i++) {
                if (!isTarget(delegations[i].poolId, targetPoolIds)) {
                    sources[idx] = delegations[i];
                    weights[idx] = delegations[i].amount;
                    idx++;
                }
            }

            uint256[] memory sourceAmounts = LibStaking.splitByWeights(surplus, weights);
            uint256[] memory targetAmounts = LibStaking.splitEqually(surplus, targetPoolIds.length);

            calls = new bytes[](sourceCount + targetPoolIds.length);
            for (uint256 i = 0; i < sourceCount; i++) {
                calls[i] = LibStaking.encodeUndelegate(sources[i].poolId, sourceAmounts[i]);
            }
            for (uint256 i = 0; i < targetPoolIds.length; i++) {
                calls[sourceCount + i] = LibStaking.encodeDelegate(targetPoolIds[i], targetAmounts[i]);
            }
        } else {
            uint256 excess = currentTarget - targetAmount;

            uint256 sourceCount = 0;
            for (uint256 i = 0; i < delegations.length; i++) {
                if (isTarget(delegations[i].poolId, targetPoolIds)) sourceCount++;
            }

            LibStaking.Delegation[] memory sources = new LibStaking.Delegation[](sourceCount);
            uint256 idx = 0;
            uint256[] memory weights = new uint256[](sourceCount);
            for (uint256 i = 0; i < delegations.length; i++) {
                if (isTarget(delegations[i].poolId, targetPoolIds)) {
                    sources[idx] = delegations[i];
                    weights[idx] = delegations[i].amount;
                    idx++;
                }
            }

            uint256[] memory undelegateAmounts = LibStaking.splitByWeights(excess, weights);
            calls = new bytes[](sourceCount);
            for (uint256 i = 0; i < sourceCount; i++) {
                calls[i] = LibStaking.encodeUndelegate(sources[i].poolId, undelegateAmounts[i]);
            }
        }
    }

    function isTarget(bytes32 poolId, bytes32[] calldata targetPoolIds)
        internal
        pure
        returns (bool)
    {
        return _isTarget(poolId, targetPoolIds);
    }

    function _isTarget(bytes32 poolId, bytes32[] calldata targetPoolIds)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < targetPoolIds.length; i++) {
            if (poolId == targetPoolIds[i]) return true;
        }
        return false;
    }
}
