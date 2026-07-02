// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibSafeChild} from "../src/libraries/LibSafeChild.sol";
import {LibSafe} from "../src/libraries/LibSafe.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {Call} from "../src/types/Types.sol";

/**
 * @title WrapGovernanceMultiDelegate
 * @notice Wraps ZRX into wZRX and splits it across N 1-of-1 child Safe wallets,
 *         each delegated to a distinct address. The child Safes are deployed
 *         deterministically from the master Safe via the official Safe proxy
 *         factory and are owned solely by the master Safe.
 */
contract WrapGovernanceMultiDelegate is Script {
    // Storage arrays keep the script flat and avoid stack-limit workarounds.
    Call[] internal _calls;
    address[] internal _childSafes;
    uint256[] internal _balancesBefore;

    /// @notice Wrap and split across child Safes. Pass staker = address(0) to use the default staker.
    function run(address staker, address[] calldata delegatees, uint256[] calldata amounts) external {
        if (staker == address(0)) staker = Constants.DEFAULT_STAKER;

        _validate(delegatees, amounts);
        uint256 total = _total(amounts);

        delete _childSafes;
        delete _balancesBefore;
        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(staker, delegatees[i]);
            _childSafes.push(childSafe);
            _balancesBefore.push(IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe));
        }

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);

        // Build all calls. If `staker` is a Safe these are batched through its
        // `execTransaction`, so every inner call originates from the master Safe.
        _calls.push(
            Call({
                target: Constants.ZRX_TOKEN,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, Constants.WZRX_TOKEN, total)
            })
        );

        for (uint256 i = 0; i < delegatees.length; i++) {
            _appendChildCalls(staker, delegatees[i], _childSafes[i], amounts[i]);
        }

        _calls.push(
            Call({
                target: Constants.ZRX_TOKEN,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, Constants.WZRX_TOKEN, 0)
            })
        );

        bool executed = LibSafe.executeCalls(staker, _calls);
        if (executed) {
            _verify(staker, delegatees, amounts, zrxBefore, total);
        }

        _clearState();
    }

    function _appendChildCalls(address staker, address delegatee, address childSafe, uint256 amount)
        private
    {
        if (childSafe.code.length == 0) {
            _calls.push(
                Call({
                    target: Constants.SAFE_PROXY_FACTORY,
                    value: 0,
                    data: LibSafeChild.deployChildSafeCalldata(staker, delegatee)
                })
            );
        }

        _calls.push(
            Call({
                target: Constants.WZRX_TOKEN,
                value: 0,
                data: abi.encodeWithSelector(IwZRX.depositFor.selector, childSafe, amount)
            })
        );

        _calls.push(
            Call({
                target: childSafe,
                value: 0,
                data: LibSafeChild.approveDelegateHashCalldata(childSafe, delegatee)
            })
        );

        _calls.push(
            Call({
                target: childSafe,
                value: 0,
                data: LibSafeChild.execDelegateCalldata(childSafe, delegatee, staker)
            })
        );
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
        address[] calldata delegatees,
        uint256[] calldata amounts,
        uint256 zrxBefore,
        uint256 total
    ) private view {
        for (uint256 i = 0; i < _childSafes.length; i++) {
            address childSafe = _childSafes[i];
            uint256 after_ = IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe);
            require(after_ - _balancesBefore[i] == amounts[i], "WrapMulti: child Safe balance mismatch");
            require(
                IwZRX(Constants.WZRX_TOKEN).delegates(childSafe) == delegatees[i],
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

    function _clearState() private {
        delete _calls;
        delete _childSafes;
        delete _balancesBefore;
    }
}
