// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {Constants} from "./Constants.sol";
import {LibStaking} from "./LibStaking.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

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

    function parseMode(string calldata modeName) internal pure returns (Mode) {
        if (keccak256(bytes(modeName)) == keccak256(bytes("unstake"))) return Mode.Unstake;
        if (keccak256(bytes(modeName)) == keccak256(bytes("full"))) return Mode.Full;
        if (keccak256(bytes(modeName)) == keccak256(bytes("liquid"))) return Mode.Liquid;
        if (keccak256(bytes(modeName)) == keccak256(bytes("exclude-pools"))) return Mode.ExcludePools;
        revert("unknown mode");
    }

    function _unstake(address staker, uint256 amount) internal {
        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        vm.stopBroadcast();
    }

    function _wrapLiquid(address staker, address delegatee, uint256 amount) internal {
        vm.startBroadcast(staker);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();
    }

    function _wrapFull(address staker, address delegatee, uint256 amount) internal {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(totalDelegated > 0, "no delegated stake");

        bytes[] memory undelegateCalls = new bytes[](delegations.length);
        for (uint256 i = 0; i < delegations.length; i++) {
            undelegateCalls[i] = LibStaking.encodeUndelegate(delegations[i].poolId, delegations[i].amount);
        }

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();
    }

    function _wrapExcludePools(
        address staker,
        address delegatee,
        uint256 amount,
        bytes32[] calldata excludePoolIds
    ) internal {
        (LibStaking.Delegation[] memory delegations, uint256 totalDelegated) =
            LibStaking.getActiveDelegations(Constants.STAKING_PROXY, staker, MAX_POOL_ID);
        require(totalDelegated > 0, "no delegated stake");

        uint256 sourceCount = 0;
        uint256 sourceTotal = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            if (!isExcluded(delegations[i].poolId, excludePoolIds)) {
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
            if (!isExcluded(delegations[i].poolId, excludePoolIds)) {
                sources[idx] = delegations[i];
                weights[idx] = delegations[i].amount;
                idx++;
            }
        }

        uint256[] memory undelegateAmounts = LibStaking.splitByWeights(amount, weights);
        bytes[] memory undelegateCalls = new bytes[](sourceCount);
        for (uint256 i = 0; i < sourceCount; i++) {
            undelegateCalls[i] = LibStaking.encodeUndelegate(sources[i].poolId, undelegateAmounts[i]);
        }

        vm.startBroadcast(staker);
        IStakingProxy(Constants.STAKING_PROXY).batchExecute(undelegateCalls);
        _advanceEpoch();
        IStakingProxy(Constants.STAKING_PROXY).endEpoch();
        IStakingProxy(Constants.STAKING_PROXY).unstake(amount);
        _approveWrapDelegateReset(staker, delegatee, amount);
        vm.stopBroadcast();
    }

    function _approveWrapDelegateReset(address staker, address delegatee, uint256 amount) internal {
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, amount);
        IwZRX(Constants.WZRX_TOKEN).depositFor(staker, amount);
        IwZRX(Constants.WZRX_TOKEN).delegate(delegatee);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, 0);
    }

    function _advanceEpoch() internal {
        IStakingProxy stake = IStakingProxy(Constants.STAKING_PROXY);
        uint256 startTime = stake.currentEpochStartTimeInSeconds();
        uint256 duration = stake.epochDurationInSeconds();
        vm.warp(startTime + duration + 1);
    }

    function isExcluded(bytes32 poolId, bytes32[] calldata excludePoolIds)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < excludePoolIds.length; i++) {
            if (poolId == excludePoolIds[i]) return true;
        }
        return false;
    }
}
