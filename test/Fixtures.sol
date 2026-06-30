// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Constants} from "../src/constants/Constants.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

/**
 * @title ZrxFixture
 * @notice Common test setup helpers for ZRX staking operations.
 */
contract ZrxFixture is Test {
    function _createFork() internal {
        vm.createSelectFork(vm.envString("RPC_URL"), Constants.FORK_BLOCK_NUMBER);
    }

    function _giveZrx(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(0)));
        vm.store(Constants.ZRX_TOKEN, slot, bytes32(amount));
        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(account), amount, "zrx balance");
    }

    function _rollEpoch() internal {
        IStakingProxy stake = IStakingProxy(Constants.STAKING_PROXY);
        uint256 start = stake.currentEpochStartTimeInSeconds();
        uint256 duration = stake.epochDurationInSeconds();
        vm.warp(start + duration + 1);
        stake.endEpoch();
    }

    /// @dev Build a comma-separated string of pool ids for script CSV inputs.
    function _poolsToCsv(bytes32[] memory pools) internal pure returns (string memory csv) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (i > 0) csv = string.concat(csv, ",");
            csv = string.concat(csv, vm.toString(pools[i]));
        }
    }
}
