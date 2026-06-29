// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";
import {LibStaking} from "./LibStaking.sol";
import {LibScript} from "./LibScript.sol";
import {Constants} from "./Constants.sol";

/**
 * @title StakeAndDelegate
 * @notice Stakes ZRX through the 0x staking proxy and delegates across a set of pools.
 */
contract StakeAndDelegate is Script {
    using LibScript for *;

    function run(address staker, uint256 stakeAmount, uint256 delegateAmount, bytes32[] calldata pools)
        external
    {
        require(staker != address(0), "Invalid staker");
        require(pools.length > 0, "Empty pool list");

        uint256 actualDelegate = delegateAmount == 0 && stakeAmount > 0 ? stakeAmount : delegateAmount;

        if (LibScript.envBool("WRITE_PLAN", false)) {
            LibScript.emitPlanJson(_buildSteps(stakeAmount, actualDelegate, pools));
            return;
        }

        IStakingProxy staking = IStakingProxy(Constants.STAKING_PROXY);
        IERC20 zrx = IERC20(Constants.ZRX_TOKEN);

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
    }

    function _buildSteps(uint256 stakeAmount, uint256 delegateAmount, bytes32[] calldata pools)
        internal
        pure
        returns (LibScript.PlanStep[] memory steps)
    {
        uint256 stepCount = (stakeAmount > 0 ? 2 : 0) + (delegateAmount > 0 ? pools.length : 0);
        steps = new LibScript.PlanStep[](stepCount);
        uint256 idx;
        if (stakeAmount > 0) {
            steps[idx] = LibScript.PlanStep({
                to: Constants.ZRX_TOKEN,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, Constants.ERC20_PROXY, stakeAmount),
                description: "Approve ERC20 Asset Proxy for staking"
            });
            idx++;
            steps[idx] = LibScript.PlanStep({
                to: Constants.STAKING_PROXY,
                value: 0,
                data: abi.encodeWithSelector(IStakingProxy.stake.selector, stakeAmount),
                description: "Stake ZRX"
            });
            idx++;
        }
        if (delegateAmount > 0) {
            uint256[] memory parts = LibStaking.splitEqually(delegateAmount, pools.length);
            for (uint256 i = 0; i < pools.length; i++) {
                steps[idx] = LibScript.PlanStep({
                    to: Constants.STAKING_PROXY,
                    value: 0,
                    data: LibStaking.encodeDelegate(pools[i], parts[i]),
                    description: string.concat("Delegate ", vm.toString(parts[i]), " to pool ", vm.toString(pools[i]))
                });
                idx++;
            }
        }
    }
}
