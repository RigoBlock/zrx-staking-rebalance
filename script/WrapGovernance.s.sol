// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

/**
 * @title WrapGovernance
 * @notice Wraps ZRX into the wZRX governance token and delegates voting power.
 */
contract WrapGovernance is Script {
    uint256 internal constant MAX_POOL_ID = 100;
    uint8 internal constant UNDELEGATED = 0;

    enum Mode {
        Unstake,
        Full,
        Liquid,
        ExcludePools
    }

    /// @notice Run using the default staker, default delegatee, and default exclude pools.
    function run(uint8 mode) external {
        _run(
            _validateMode(mode),
            Constants.DEFAULT_STAKER,
            Constants.DEFAULT_DELEGATEE,
            LibStaking.defaultTargetPools()
        );
    }

    /// @notice Run with explicit staker, delegatee, and exclude pools (used by tests).
    function run(
        uint8 mode,
        address staker,
        address delegatee,
        bytes32[] calldata excludePoolIds
    ) external {
        _run(_validateMode(mode), staker, delegatee, excludePoolIds);
    }

    function _run(uint8 mode, address staker, address delegatee, bytes32[] memory excludePoolIds)
        private
    {
        if (mode == uint8(Mode.Unstake)) {
            _unstake(staker);
        } else if (mode == uint8(Mode.Liquid)) {
            _wrapLiquid(staker, delegatee);
        } else if (mode == uint8(Mode.Full)) {
            _wrapFull(staker, delegatee);
        } else {
            _wrapExcludePools(staker, delegatee, excludePoolIds);
        }

        console2.log("WrapGovernance done");
    }

    function _validateMode(uint8 mode) private pure returns (uint8) {
        require(mode <= uint8(Mode.ExcludePools), "invalid mode");
        return mode;
    }

    function _unstake(address staker) private {
        IStakingProxy staking = IStakingProxy(Constants.STAKING_PROXY);
        uint256 unstakeAmount = staking.getOwnerStakeByStatus(staker, UNDELEGATED).currentEpochBalance;
        require(unstakeAmount > 0, "no undelegated stake");

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);

        vm.startBroadcast(staker);
        staking.unstake(unstakeAmount);
        vm.stopBroadcast();

        require(
            IERC20(Constants.ZRX_TOKEN).balanceOf(staker) - zrxBefore == unstakeAmount,
            "WrapGovernance: unstake did not increase ZRX balance"
        );
    }

    struct WrapState {
        uint256 wzrxBefore;
        address delegateeBefore;
    }

    function _readWrapState(address staker) private view returns (WrapState memory state) {
        IwZRX wzrx = IwZRX(Constants.WZRX_TOKEN);
        state.wzrxBefore = wzrx.balanceOf(staker);
        state.delegateeBefore = wzrx.delegates(staker);
    }

    function _wrapLiquid(address staker, address delegatee) private {
        WrapState memory state = _readWrapState(staker);
        uint256 wrapAmount = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);
        require(wrapAmount > 0, "no liquid ZRX");

        vm.startBroadcast(staker);
        _approveWrapDelegateReset(staker, delegatee, wrapAmount);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, wrapAmount, state.wzrxBefore);
    }

    function _wrapFull(address staker, address delegatee) private {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(delegations.length > 0, "no delegated stake");
        require(totalDelegated > 0, "no delegated stake");

        bytes[] memory undelegateCalls = _buildUndelegateCalls(delegations);
        WrapState memory state = _readWrapState(staker);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(totalDelegated);
        _approveWrapDelegateReset(staker, delegatee, totalDelegated);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, totalDelegated, state.wzrxBefore);
        _verifyActiveDelegation(staker, 0, "WrapGovernance: full wrap left active delegations");
    }

    function _wrapExcludePools(
        address staker,
        address delegatee,
        bytes32[] memory excludePoolIds
    ) private {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(totalDelegated > 0, "no delegated stake");

        uint256 excludedTotal = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            if (_isExcluded(delegations[i].poolId, excludePoolIds)) {
                excludedTotal += delegations[i].amount;
            }
        }
        uint256 wrapAmount = totalDelegated - excludedTotal;
        require(wrapAmount > 0, "no stake to wrap");

        bytes[] memory undelegateCalls = _buildExcludeUndelegateCalls(delegations, excludePoolIds, wrapAmount);
        WrapState memory state = _readWrapState(staker);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(wrapAmount);
        _approveWrapDelegateReset(staker, delegatee, wrapAmount);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, wrapAmount, state.wzrxBefore);
        _verifyActiveDelegation(staker, totalDelegated - wrapAmount, "WrapGovernance: exclude-pools delegation mismatch");
    }

    function _approveWrapDelegateReset(address staker, address delegatee, uint256 amount) private {
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, amount);
        IwZRX(Constants.WZRX_TOKEN).depositFor(staker, amount);
        IwZRX(Constants.WZRX_TOKEN).delegate(delegatee);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, 0);
    }

    function _advanceEpoch() private {
        IStakingProxy stake = IStakingProxy(Constants.STAKING_PROXY);
        uint256 startTime = stake.currentEpochStartTimeInSeconds();
        uint256 duration = stake.epochDurationInSeconds();
        vm.warp(startTime + duration + 1);
    }

    function _verifyWrap(
        address staker,
        address expectedDelegatee,
        uint256 expectedIncrease,
        uint256 wzrxBefore
    ) private view {
        IwZRX wzrx = IwZRX(Constants.WZRX_TOKEN);
        uint256 wzrxAfter = wzrx.balanceOf(staker);
        require(wzrxAfter - wzrxBefore == expectedIncrease, "WrapGovernance: wZRX balance increase mismatch");
        require(wzrx.delegates(staker) == expectedDelegatee, "WrapGovernance: delegatee mismatch");
        // ZRX approval should always be reset to 0.
        require(
            IERC20(Constants.ZRX_TOKEN).allowance(staker, Constants.WZRX_TOKEN) == 0,
            "WrapGovernance: ZRX allowance not reset"
        );
    }

    function _verifyActiveDelegation(address staker, uint256 expectedTotal, string memory message) private view {
        (, uint256 activeTotal) = LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(activeTotal == expectedTotal, message);
    }

    function _buildUndelegateCalls(LibStaking.Delegation[] memory delegations)
        private
        pure
        returns (bytes[] memory calls)
    {
        calls = new bytes[](delegations.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            calls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }
    }

    function _buildExcludeUndelegateCalls(
        LibStaking.Delegation[] memory delegations,
        bytes32[] memory excludePoolIds,
        uint256 amount
    ) private pure returns (bytes[] memory calls) {
        uint256 sourceCount = 0;
        uint256 sourceTotal = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            if (!_isExcluded(delegations[i].poolId, excludePoolIds)) {
                sourceCount++;
                sourceTotal += delegations[i].amount;
            }
        }
        require(sourceCount > 0, "no source pools");
        require(amount <= sourceTotal, "amount exceeds source stake");

        LibStaking.Delegation[] memory sources = new LibStaking.Delegation[](sourceCount);
        uint256[] memory weights = new uint256[](sourceCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            if (!_isExcluded(delegations[i].poolId, excludePoolIds)) {
                sources[idx] = delegations[i];
                weights[idx] = delegations[i].amount;
                idx++;
            }
        }

        uint256[] memory undelegateAmounts = LibStaking.splitByWeights(amount, weights);
        calls = new bytes[](sourceCount);
        for (uint256 i = 0; i < sourceCount; i++) {
            calls[i] = LibStaking.encodeUndelegate(sources[i].poolId, undelegateAmounts[i]);
        }
    }

    function _isExcluded(bytes32 poolId, bytes32[] memory excludePoolIds) private pure returns (bool) {
        for (uint256 i = 0; i < excludePoolIds.length; i++) {
            if (poolId == excludePoolIds[i]) return true;
        }
        return false;
    }
}
