// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {LibSafe} from "../src/libraries/LibSafe.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";
import {RedelegateMode, Delegation, Call} from "../src/types/Types.sol";

/**
 * @title Redelegate
 * @notice Rebalances or removes existing ZRX delegations across the 0x staking proxy.
 */
contract Redelegate is Script {
    // Storage array for the single batched operation, keeping the script flat.
    Call[] internal _calls;

    /// @notice Execute a redelegate operation for the given staker.
    /// @param mode Operation mode (undelegate-all, redelegate-all, redelegate-amount).
    /// @param staker Staker address; pass address(0) to use the default staker.
    /// @param targetAmount For redelegate-amount, the desired total delegated amount.
    ///                     Pass 0 to target the current total delegated balance.
    ///                     Ignored for undelegate-all and redelegate-all.
    /// @param poolsCsv Comma-separated target pool ids. Empty string uses defaultTargetPools().
    function run(RedelegateMode mode, address staker, uint256 targetAmount, string memory poolsCsv)
        external
    {
        if (staker == address(0)) staker = Constants.DEFAULT_STAKER;
        require(staker != address(0), "Invalid staker");
        bytes32[] memory targetPoolIds = LibStaking.parsePools(poolsCsv);

        bytes[] memory calls = _buildCalls(mode, staker, targetAmount, targetPoolIds);
        if (calls.length == 0) {
            return;
        }

        (Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker);

        // Wrap the batched staking calls in a single operation. If `staker` is a
        // Safe this is executed through `execTransaction`.
        delete _calls;
        _calls.push(
            Call({
                target: Constants.STAKING_PROXY,
                value: 0,
                data: abi.encodeWithSelector(IStakingProxy.batchExecute.selector, calls)
            })
        );

        bool executed = LibSafe.executeCalls(staker, _calls);
        if (executed) {
            _verify(mode, staker, targetAmount, targetPoolIds, delegations, totalDelegated);
        }
    }

    function _buildCalls(
        RedelegateMode mode,
        address staker,
        uint256 targetAmount,
        bytes32[] memory targetPoolIds
    ) private view returns (bytes[] memory calls) {
        (Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker);

        require(totalDelegated > 0, "no delegated stake");

        if (mode == RedelegateMode.UndelegateAll) {
            calls = _buildUndelegateCalls(delegations);
        } else if (mode == RedelegateMode.RedelegateAll) {
            require(targetPoolIds.length > 0, "no target pools");
            calls = _buildRebalanceCalls(delegations, targetPoolIds, totalDelegated);
        } else {
            require(targetPoolIds.length > 0, "no target pools");
            uint256 effectiveTarget = targetAmount == 0 ? totalDelegated : targetAmount;
            calls = _buildRedelegateAmountCalls(delegations, targetPoolIds, effectiveTarget);
        }
    }

    function _verify(
        RedelegateMode mode,
        address staker,
        uint256 targetAmount,
        bytes32[] memory targetPoolIds,
        Delegation[] memory beforeDelegations,
        uint256 totalDelegatedBefore
    ) private view {
        if (mode == RedelegateMode.UndelegateAll) {
            // Every previously active delegation must be scheduled for removal.
            for (uint256 i = 0; i < beforeDelegations.length; i++) {
                uint256 next_ =
                    IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, beforeDelegations[i].poolId)
                .nextEpochBalance;
                require(next_ == 0, "Redelegate: undelegate-all left scheduled stake");
            }
            return;
        }

        // For redelegate modes, no stake may remain scheduled outside the target pools.
        uint256 lastPoolId_ = uint256(IStakingProxy(Constants.STAKING_PROXY).lastPoolId());
        for (uint256 i = 1; i <= lastPoolId_; i++) {
            bytes32 poolId = bytes32(i);
            uint256 next_ =
                IStakingProxy(Constants.STAKING_PROXY)
            .getStakeDelegatedToPoolByOwner(staker, poolId)
            .nextEpochBalance;
            if (next_ > 0 && !_isTarget(poolId, targetPoolIds)) {
                revert("Redelegate: non-target pool has scheduled stake");
            }
        }

        if (mode == RedelegateMode.RedelegateAll) {
            uint256 expectedTotal = totalDelegatedBefore;
            uint256[] memory parts = LibStaking.splitEqually(expectedTotal, targetPoolIds.length);
            uint256 scheduledTotal = 0;
            for (uint256 i = 0; i < targetPoolIds.length; i++) {
                uint256 next_ =
                    IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, targetPoolIds[i])
                .nextEpochBalance;
                require(next_ == parts[i], "Redelegate: redelegate-all pool amount mismatch");
                scheduledTotal += next_;
            }
            require(scheduledTotal == expectedTotal, "Redelegate: redelegate-all total mismatch");
        } else {
            // RedelegateAmount
            uint256 expectedTotal = targetAmount == 0 ? totalDelegatedBefore : targetAmount;
            uint256 scheduledTotal = 0;
            for (uint256 i = 0; i < targetPoolIds.length; i++) {
                scheduledTotal += IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, targetPoolIds[i])
                .nextEpochBalance;
            }
            require(scheduledTotal == expectedTotal, "Redelegate: redelegate-amount total mismatch");
        }
    }

    function _buildUndelegateCalls(Delegation[] memory delegations)
        private
        pure
        returns (bytes[] memory calls)
    {
        calls = new bytes[](delegations.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            calls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }
    }

    function _buildRebalanceCalls(
        Delegation[] memory delegations,
        bytes32[] memory targetPoolIds,
        uint256 targetTotal
    ) private pure returns (bytes[] memory calls) {
        calls = new bytes[](delegations.length + targetPoolIds.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            calls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }
        uint256[] memory parts = LibStaking.splitEqually(targetTotal, targetPoolIds.length);
        for (uint256 i = 0; i < targetPoolIds.length; i++) {
            calls[delegations.length + i] = LibStaking.encodeDelegate(targetPoolIds[i], parts[i]);
        }
    }

    function _buildRedelegateAmountCalls(
        Delegation[] memory delegations,
        bytes32[] memory targetPoolIds,
        uint256 targetAmount
    ) private pure returns (bytes[] memory calls) {
        uint256 currentTarget = 0;
        uint256 nonTargetTotal = 0;

        for (uint256 i = 0; i < delegations.length; i++) {
            if (_isTarget(delegations[i].poolId, targetPoolIds)) {
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
                if (!_isTarget(delegations[i].poolId, targetPoolIds)) sourceCount++;
            }

            Delegation[] memory sources = new Delegation[](sourceCount);
            uint256 idx = 0;
            uint256[] memory weights = new uint256[](sourceCount);
            for (uint256 i = 0; i < delegations.length; i++) {
                if (!_isTarget(delegations[i].poolId, targetPoolIds)) {
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
                calls[sourceCount + i] =
                    LibStaking.encodeDelegate(targetPoolIds[i], targetAmounts[i]);
            }
        } else {
            uint256 excess = currentTarget - targetAmount;

            uint256 sourceCount = 0;
            for (uint256 i = 0; i < delegations.length; i++) {
                if (_isTarget(delegations[i].poolId, targetPoolIds)) sourceCount++;
            }

            Delegation[] memory sources = new Delegation[](sourceCount);
            uint256 idx = 0;
            uint256[] memory weights = new uint256[](sourceCount);
            for (uint256 i = 0; i < delegations.length; i++) {
                if (_isTarget(delegations[i].poolId, targetPoolIds)) {
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

    function _isTarget(bytes32 poolId, bytes32[] memory targetPoolIds) private pure returns (bool) {
        for (uint256 i = 0; i < targetPoolIds.length; i++) {
            if (poolId == targetPoolIds[i]) return true;
        }
        return false;
    }
}
