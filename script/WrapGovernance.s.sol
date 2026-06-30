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

    function run(
        string calldata modeName,
        address staker,
        address delegatee,
        uint256 amount,
        bytes32[] calldata excludePoolIds
    ) external {
        Mode mode = parseMode(modeName);

        if (mode == Mode.Unstake) {
            _unstake(staker, amount);
        } else if (mode == Mode.Liquid) {
            _wrapLiquid(staker, delegatee, amount);
        } else if (mode == Mode.Full) {
            _wrapFull(staker, delegatee, amount);
        } else {
            _wrapExcludePools(staker, delegatee, amount, excludePoolIds);
        }

        console2.log("WrapGovernance done");
    }

    function parseMode(string calldata modeName) private pure returns (Mode) {
        if (keccak256(bytes(modeName)) == keccak256(bytes("unstake"))) return Mode.Unstake;
        if (keccak256(bytes(modeName)) == keccak256(bytes("full"))) return Mode.Full;
        if (keccak256(bytes(modeName)) == keccak256(bytes("liquid"))) return Mode.Liquid;
        if (keccak256(bytes(modeName)) == keccak256(bytes("exclude-pools"))) return Mode.ExcludePools;
        revert("unknown mode");
    }

    function _unstake(address staker, uint256 amount) private {
        IERC20 zrx = IERC20(Constants.ZRX_TOKEN);
        uint256 zrxBefore = zrx.balanceOf(staker);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        vm.stopBroadcast();

        require(
            zrx.balanceOf(staker) - zrxBefore == amount,
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

    function _wrapLiquid(address staker, address delegatee, uint256 amount) private {
        WrapState memory state = _readWrapState(staker);

        vm.startBroadcast(staker);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, amount, state.wzrxBefore);
    }

    function _wrapFull(address staker, address delegatee, uint256 amount) private {
        (LibStaking.Delegation[] memory delegations,) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(delegations.length > 0, "no delegated stake");

        bytes[] memory undelegateCalls = _buildUndelegateCalls(delegations);
        WrapState memory state = _readWrapState(staker);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, amount, state.wzrxBefore);
        _verifyActiveDelegation(staker, 0, "WrapGovernance: full wrap left active delegations");
    }

    function _wrapExcludePools(
        address staker,
        address delegatee,
        uint256 amount,
        bytes32[] calldata excludePoolIds
    ) private {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(totalDelegated > 0, "no delegated stake");

        bytes[] memory undelegateCalls = _buildExcludeUndelegateCalls(delegations, excludePoolIds, amount);
        WrapState memory state = _readWrapState(staker);

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();

        _verifyWrap(staker, delegatee, amount, state.wzrxBefore);
        _verifyActiveDelegation(staker, totalDelegated - amount, "WrapGovernance: exclude-pools delegation mismatch");
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
        bytes32[] calldata excludePoolIds,
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

    function _isExcluded(bytes32 poolId, bytes32[] calldata excludePoolIds) private pure returns (bool) {
        for (uint256 i = 0; i < excludePoolIds.length; i++) {
            if (poolId == excludePoolIds[i]) return true;
        }
        return false;
    }
}
