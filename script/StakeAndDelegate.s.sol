// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {LibSafe} from "../src/libraries/LibSafe.sol";
import {Constants} from "../src/constants/Constants.sol";
import {Call} from "../src/types/Types.sol";

/**
 * @title StakeAndDelegate
 * @notice Stakes ZRX through the 0x staking proxy and delegates equally across a set of pools.
 */
contract StakeAndDelegate is Script {
    // Storage arrays are used here instead of memory locals so the script can be
    // written in a flat, readable style without hitting the Solidity stack limit.
    bytes32[] internal _pools;
    Call[] internal _calls;
    uint256[] internal _beforePerPool;

    /// @notice Stake and/or delegate for the given staker.
    /// @param staker Staker address; pass address(0) to use the default staker.
    /// @param stakeAmount ZRX to stake. Pass USE_FULL_BALANCE to stake the entire ZRX balance.
    /// @param delegateAmount ZRX to delegate. Pass USE_FULL_BALANCE to delegate the full staked + undelegated balance.
    ///                       Pass 0 with stakeAmount > 0 to delegate exactly the staked amount.
    /// @param poolsCsv Comma-separated target pool ids. Empty string uses defaultTargetPools().
    function run(
        address staker,
        uint256 stakeAmount,
        uint256 delegateAmount,
        string memory poolsCsv
    ) external {
        if (staker == address(0)) staker = Constants.DEFAULT_STAKER;
        require(staker != address(0), "Invalid staker");

        _pools = LibStaking.parsePools(poolsCsv);
        require(_pools.length > 0, "Empty pool list");

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);
        uint256 actualStake = stakeAmount == Constants.USE_FULL_BALANCE ? zrxBefore : stakeAmount;
        uint256 actualDelegate;
        if (delegateAmount == Constants.USE_FULL_BALANCE) {
            uint256 undelegatedBefore =
                IStakingProxy(Constants.STAKING_PROXY)
            .getOwnerStakeByStatus(staker, LibStaking.UNDELEGATED)
            .currentEpochBalance;
            actualDelegate = actualStake + undelegatedBefore;
        } else if (delegateAmount == 0 && actualStake > 0) {
            actualDelegate = actualStake;
        } else {
            actualDelegate = delegateAmount;
        }

        if (actualStake > 0) {
            require(zrxBefore >= actualStake, "Insufficient ZRX balance");
            _calls.push(
                Call({
                    target: Constants.ZRX_TOKEN,
                    value: 0,
                    data: abi.encodeWithSelector(
                        IERC20.approve.selector, Constants.ERC20_PROXY, actualStake
                    )
                })
            );
            _calls.push(
                Call({
                    target: Constants.STAKING_PROXY,
                    value: 0,
                    data: abi.encodeWithSelector(IStakingProxy.stake.selector, actualStake)
                })
            );
        }

        if (actualDelegate > 0) {
            uint256[] memory parts = LibStaking.splitEqually(actualDelegate, _pools.length);
            bytes[] memory delegateCalls = new bytes[](_pools.length);
            for (uint256 i = 0; i < _pools.length; i++) {
                delegateCalls[i] = LibStaking.encodeDelegate(_pools[i], parts[i]);
            }
            _calls.push(
                Call({
                    target: Constants.STAKING_PROXY,
                    value: 0,
                    data: abi.encodeWithSelector(IStakingProxy.batchExecute.selector, delegateCalls)
                })
            );
        }

        if (actualStake > 0) {
            _calls.push(
                Call({
                    target: Constants.ZRX_TOKEN,
                    value: 0,
                    data: abi.encodeWithSelector(IERC20.approve.selector, Constants.ERC20_PROXY, 0)
                })
            );
        }

        if (_calls.length == 0) {
            _clearState();
            return;
        }

        _snapshotNextEpochBalances(staker);
        uint256 scheduledBefore = _sum(_beforePerPool);

        bool executed = LibSafe.executeCalls(staker, _calls);
        if (executed) {
            _verify(staker, actualStake, actualDelegate, scheduledBefore, zrxBefore);
        }

        _clearState();
        console2.log("StakeAndDelegate done");
    }

    function _verify(
        address staker,
        uint256 stakeAmount,
        uint256 delegateAmount,
        uint256 scheduledBefore,
        uint256 zrxBefore
    ) private view {
        IStakingProxy staking = IStakingProxy(Constants.STAKING_PROXY);

        if (delegateAmount > 0) {
            uint256[] memory parts = LibStaking.splitEqually(delegateAmount, _pools.length);
            uint256 scheduledAfter = 0;
            for (uint256 i = 0; i < _pools.length; i++) {
                uint256 expected = _beforePerPool[i] + parts[i];
                uint256 after_ =
                    staking.getStakeDelegatedToPoolByOwner(staker, _pools[i]).nextEpochBalance;
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

    function _snapshotNextEpochBalances(address staker) private {
        delete _beforePerPool;
        for (uint256 i = 0; i < _pools.length; i++) {
            _beforePerPool.push(
                IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, _pools[i])
                .nextEpochBalance
            );
        }
    }

    function _sum(uint256[] memory values) private pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
    }

    function _clearState() private {
        delete _calls;
        delete _pools;
        delete _beforePerPool;
    }
}
