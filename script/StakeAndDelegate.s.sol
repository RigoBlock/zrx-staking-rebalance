// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {Constants} from "../src/constants/Constants.sol";

/**
 * @title StakeAndDelegate
 * @notice Stakes ZRX through the 0x staking proxy and delegates across a set of pools.
 */
contract StakeAndDelegate is Script {
    uint256 internal constant MAX_POOL_ID = 100;

    function run(address staker, uint256 stakeAmount, uint256 delegateAmount, bytes32[] calldata pools)
        external
    {
        require(staker != address(0), "Invalid staker");
        require(pools.length > 0, "Empty pool list");

        uint256 actualDelegate = delegateAmount == 0 && stakeAmount > 0 ? stakeAmount : delegateAmount;

        IStakingProxy staking = IStakingProxy(Constants.STAKING_PROXY);
        IERC20 zrx = IERC20(Constants.ZRX_TOKEN);

        // Snapshot state before execution so post-conditions are robust to pre-existing balances.
        uint256[] memory beforePerPool = _snapshotNextEpochBalances(staker, pools);
        uint256 scheduledBefore = _sum(beforePerPool);
        uint256 zrxBefore = zrx.balanceOf(staker);

        vm.startBroadcast(staker);

        if (stakeAmount > 0) {
            require(zrx.balanceOf(staker) >= stakeAmount, "Insufficient ZRX balance");
            zrx.approve(Constants.ERC20_PROXY, stakeAmount);
            staking.stake(stakeAmount);
        }

        if (actualDelegate > 0) {
            uint256[] memory parts = LibStaking.splitEqually(actualDelegate, pools.length);
            bytes[] memory calls = new bytes[](pools.length);
            for (uint256 i = 0; i < pools.length; i++) {
                calls[i] = LibStaking.encodeDelegate(pools[i], parts[i]);
            }
            staking.batchExecute(calls);
        }

        zrx.approve(Constants.ERC20_PROXY, 0);

        vm.stopBroadcast();

        _verify(staker, stakeAmount, actualDelegate, pools, beforePerPool, scheduledBefore, zrxBefore);
    }

    function _verify(
        address staker,
        uint256 stakeAmount,
        uint256 delegateAmount,
        bytes32[] calldata pools,
        uint256[] memory beforePerPool,
        uint256 scheduledBefore,
        uint256 zrxBefore
    ) private view {
        IStakingProxy staking = IStakingProxy(Constants.STAKING_PROXY);

        if (delegateAmount > 0) {
            uint256[] memory parts = LibStaking.splitEqually(delegateAmount, pools.length);
            uint256 scheduledAfter = 0;
            for (uint256 i = 0; i < pools.length; i++) {
                uint256 expected = beforePerPool[i] + parts[i];
                uint256 after_ = staking.getStakeDelegatedToPoolByOwner(staker, pools[i]).nextEpochBalance;
                require(after_ == expected, "StakeAndDelegate: pool delegation mismatch");
                scheduledAfter += after_;
            }
            require(
                scheduledAfter - scheduledBefore == delegateAmount,
                "StakeAndDelegate: total delegation mismatch"
            );
        }

        if (stakeAmount > 0) {
            uint256 zrxAfter = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);
            require(zrxBefore - zrxAfter == stakeAmount, "StakeAndDelegate: ZRX spend mismatch");
        }
    }

    function _snapshotNextEpochBalances(address staker, bytes32[] calldata pools)
        private
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            balances[i] = IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, pools[i]).nextEpochBalance;
        }
    }

    function _sum(uint256[] memory values) private pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
    }
}
