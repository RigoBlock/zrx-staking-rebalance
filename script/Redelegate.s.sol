// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "./Constants.sol";
import {LibStaking} from "./LibStaking.sol";
import {LibScript} from "./LibScript.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

contract Redelegate is Script {
    uint256 internal constant MAX_POOL_ID = 100;

    enum Mode {
        UndelegateAll,
        RedelegateAll,
        RedelegateAmount
    }

    function run(string calldata modeName, address staker, uint256 targetAmount, bytes32[] calldata targetPoolIds)
        external
    {
        Mode mode = parseMode(modeName);

        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);

        require(totalDelegated > 0, "no delegated stake");

        bytes[] memory calls;

        if (mode == Mode.UndelegateAll) {
            calls = buildUndelegateCalls(delegations);
        } else if (mode == Mode.RedelegateAll) {
            require(targetPoolIds.length > 0, "no target pools");
            calls = buildRebalanceCalls(delegations, targetPoolIds, totalDelegated);
        } else {
            require(targetPoolIds.length > 0, "no target pools");
            calls = buildRedelegateAmountCalls(delegations, targetPoolIds, targetAmount);
        }

        if (calls.length == 0) {
            return;
        }

        LibScript.PlanStep[] memory steps = new LibScript.PlanStep[](1);
        steps[0] = LibScript.PlanStep({
            to: Constants.STAKING_PROXY,
            value: 0,
            data: abi.encodeWithSelector(IStakingProxy.batchExecute.selector, calls),
            description: "Redelegate"
        });

        if (LibScript.envBool("WRITE_PLAN", false)) {
            LibScript.emitPlanJson(steps);
            return;
        }

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(calls);
        vm.stopBroadcast();

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
        for (uint256 i = 0; i < targetPoolIds.length; i++) {
            if (poolId == targetPoolIds[i]) return true;
        }
        return false;
    }
}
