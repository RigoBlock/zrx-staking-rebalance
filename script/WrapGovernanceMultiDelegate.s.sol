// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "./Constants.sol";
import {LibScript} from "./LibScript.sol";
import {LibSafeChild} from "./LibSafeChild.sol";
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
    function plan(address staker, address[] calldata delegatees, uint256[] calldata amounts)
        external
        view
        returns (LibScript.PlanStep[] memory steps)
    {
        _validate(delegatees, amounts);
        uint256 total = _total(amounts);

        uint256 stepCount = 2; // initial approve + final reset
        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(staker, delegatees[i]);
            stepCount += 3; // deposit + approveHash + execTransaction
            if (childSafe.code.length == 0) stepCount++;
        }

        steps = new LibScript.PlanStep[](stepCount);
        uint256 idx;

        steps[idx++] = LibScript.PlanStep({
            to: Constants.ZRX_TOKEN,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, Constants.WZRX_TOKEN, total),
            description: "Approve wZRX to spend ZRX"
        });

        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(staker, delegatees[i]);

            if (childSafe.code.length == 0) {
                steps[idx++] = LibScript.PlanStep({
                    to: Constants.SAFE_PROXY_FACTORY,
                    value: 0,
                    data: LibSafeChild.deployChildSafeCalldata(staker, delegatees[i]),
                    description: string.concat("Deploy 1/1 Safe for delegatee ", vm.toString(delegatees[i]))
                });
            }

            steps[idx++] = LibScript.PlanStep({
                to: Constants.WZRX_TOKEN,
                value: 0,
                data: abi.encodeWithSelector(IwZRX.depositFor.selector, childSafe, amounts[i]),
                description: string.concat("Deposit ", vm.toString(amounts[i]), " wZRX into Safe ", vm.toString(childSafe))
            });

            steps[idx++] = LibScript.PlanStep({
                to: childSafe,
                value: 0,
                data: LibSafeChild.approveDelegateHashCalldata(childSafe, delegatees[i]),
                description: string.concat("Approve delegate tx on Safe ", vm.toString(childSafe))
            });

            steps[idx++] = LibScript.PlanStep({
                to: childSafe,
                value: 0,
                data: LibSafeChild.execDelegateCalldata(childSafe, delegatees[i], staker),
                description: string.concat("Execute delegate tx on Safe ", vm.toString(childSafe))
            });
        }

        steps[idx++] = LibScript.PlanStep({
            to: Constants.ZRX_TOKEN,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, Constants.WZRX_TOKEN, 0),
            description: "Reset ZRX approval"
        });
    }

    function run(address staker, address[] calldata delegatees, uint256[] calldata amounts) external {
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

    function _validate(address[] calldata delegatees, uint256[] calldata amounts) internal pure {
        require(delegatees.length > 0, "empty delegatee list");
        require(delegatees.length == amounts.length, "delegatee/amount length mismatch");
        for (uint256 i = 0; i < delegatees.length; i++) {
            require(delegatees[i] != address(0), "invalid delegatee");
            require(amounts[i] > 0, "invalid amount");
        }
    }

    function _total(uint256[] calldata amounts) internal pure returns (uint256 total) {
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
    ) internal view {
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
