// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibSafeChild} from "../src/libraries/LibSafeChild.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";

/**
 * @title WrapGovernanceMultiDelegate
 * @notice Wraps ZRX into wZRX and splits it across N 1-of-1 child Safe wallets,
 *         each delegated to a distinct address. The child Safes are deployed
 *         deterministically from the master Safe via the official Safe proxy
 *         factory and are owned solely by the master Safe.
 */
contract WrapGovernanceMultiDelegate is Script {
    function run(address[] calldata delegatees, uint256[] calldata amounts) external {
        _run(Constants.DEFAULT_STAKER, delegatees, amounts);
    }

    function run(address staker, address[] calldata delegatees, uint256[] calldata amounts) external {
        _run(staker, delegatees, amounts);
    }

    function _run(address staker, address[] calldata delegatees, uint256[] calldata amounts) private {
        _validate(delegatees, amounts);
        uint256 total = _total(amounts);

        address[] memory childSafes = new address[](delegatees.length);
        uint256[] memory balancesBefore = new uint256[](delegatees.length);
        for (uint256 i = 0; i < delegatees.length; i++) {
            childSafes[i] = LibSafeChild.predictChildSafeAddress(staker, delegatees[i]);
            balancesBefore[i] = IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafes[i]);
        }

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);

        vm.startBroadcast(staker);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, total);
        for (uint256 i = 0; i < delegatees.length; i++) {
            if (childSafes[i].code.length == 0) {
                childSafes[i] = LibSafeChild.deployChildSafe(staker, delegatees[i]);
            }
            IwZRX(Constants.WZRX_TOKEN).depositFor(childSafes[i], amounts[i]);
            LibSafeChild.approveAndExecDelegate(childSafes[i], delegatees[i], staker);
        }
        IERC20(Constants.ZRX_TOKEN).approve(Constants.WZRX_TOKEN, 0);
        vm.stopBroadcast();

        _verify(staker, childSafes, delegatees, amounts, balancesBefore, zrxBefore, total);
    }

    function _validate(address[] calldata delegatees, uint256[] calldata amounts) private pure {
        require(delegatees.length > 0, "empty delegatee list");
        require(delegatees.length == amounts.length, "delegatee/amount length mismatch");
        for (uint256 i = 0; i < delegatees.length; i++) {
            require(delegatees[i] != address(0), "invalid delegatee");
            require(amounts[i] > 0, "invalid amount");
        }
    }

    function _total(uint256[] calldata amounts) private pure returns (uint256 total) {
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
    }

    function _verify(
        address staker,
        address[] memory childSafes,
        address[] calldata delegatees,
        uint256[] calldata amounts,
        uint256[] memory balancesBefore,
        uint256 zrxBefore,
        uint256 total
    ) private view {
        for (uint256 i = 0; i < childSafes.length; i++) {
            uint256 after_ = IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafes[i]);
            require(after_ - balancesBefore[i] == amounts[i], "WrapMulti: child Safe balance mismatch");
            require(
                IwZRX(Constants.WZRX_TOKEN).delegates(childSafes[i]) == delegatees[i],
                "WrapMulti: child Safe delegatee mismatch"
            );
        }
        require(
            IERC20(Constants.ZRX_TOKEN).balanceOf(staker) == zrxBefore - total,
            "WrapMulti: ZRX spend mismatch"
        );
        require(
            IERC20(Constants.ZRX_TOKEN).allowance(staker, Constants.WZRX_TOKEN) == 0,
            "WrapMulti: allowance not reset"
        );
    }
}
