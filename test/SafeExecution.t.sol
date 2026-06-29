// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Constants} from "../script/Constants.sol";
import {LibScript} from "../script/LibScript.sol";
import {StakeAndDelegate} from "../script/StakeAndDelegate.s.sol";
import {Redelegate} from "../script/Redelegate.s.sol";
import {WrapGovernance} from "../script/WrapGovernance.s.sol";
import {WrapGovernanceMultiDelegate} from "../script/WrapGovernanceMultiDelegate.s.sol";
import {LibSafeChild} from "../script/LibSafeChild.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

/**
 * @title SafeExecution
 * @notice Simulates executing the proposed Safe calldata from the Safe address itself.
 */
contract SafeExecutionTest is Test {
    address internal safe;
    address internal delegatee;
    bytes32[] internal targetPools;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"), Constants.FORK_BLOCK_NUMBER);
        safe = Constants.OX_LABS_DEPLOYMENT_SAFE;
        delegatee = vm.addr(2);
        targetPools = [Constants.TARGET_POOL_31, Constants.TARGET_POOL_48, Constants.TARGET_POOL_34];
    }

    function testSafeStakeAndDelegate() public {
        _giveZrx(safe, 1000 ether);

        bytes32[] memory pools = new bytes32[](2);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(safe);
        LibScript.PlanStep[] memory steps =
            new StakeAndDelegate().plan(safe, 100 ether, 100 ether, pools);

        _executeSteps(steps, safe);

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_48);

        assertEq(bal31.nextEpochBalance, 50 ether, "pool 31 delegation");
        assertEq(bal48.nextEpochBalance, 50 ether, "pool 48 delegation");
        assertEq(zrxBefore - IERC20(Constants.ZRX_TOKEN).balanceOf(safe), 100 ether, "ZRX spent");
    }

    function testSafeRedelegateAll() public {
        _giveZrx(safe, 1000 ether);

        // Seed a single pool and roll the epoch so the delegation is active.
        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        _safeRunStakeAndDelegate(safe, seedPools, 500 ether);
        _rollEpoch();

        LibScript.PlanStep[] memory steps =
            new Redelegate().plan("redelegate-all", safe, 0, targetPools);
        _executeSteps(steps, safe);

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_48);
        IStakingProxy.StoredBalance memory bal34 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_34);

        assertEq(bal31.nextEpochBalance + bal48.nextEpochBalance + bal34.nextEpochBalance, 500 ether, "total");
        assertGt(bal31.nextEpochBalance, 0, "pool 31");
        assertGt(bal48.nextEpochBalance, 0, "pool 48");
        assertGt(bal34.nextEpochBalance, 0, "pool 34");
    }

    function testSafeWrapLiquid() public {
        _giveZrx(safe, 1000 ether);

        bytes32[] memory empty = new bytes32[](0);
        LibScript.PlanStep[] memory steps =
            new WrapGovernance().plan("liquid", safe, delegatee, 50 ether, empty);
        _executeSteps(steps, safe);

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 50 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");
    }

    function testSafeWrapFull() public {
        _giveZrx(safe, 1000 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        _safeRunStakeAndDelegate(safe, seedPools, 500 ether);
        _rollEpoch();

        bytes32[] memory empty = new bytes32[](0);
        LibScript.PlanStep[] memory steps =
            new WrapGovernance().plan("full", safe, delegatee, 500 ether, empty);

        // Step 0 undelegates the active stake. The epoch must then advance before the unstake can occur.
        require(steps.length > 1, "empty plan");
        _executeStep(steps[0], safe);
        _rollEpoch();

        for (uint256 i = 1; i < steps.length; i++) {
            _executeStep(steps[i], safe);
        }

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 500 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        assertEq(bal31.currentEpochBalance, 0, "stake undelegated");
    }

    function testSafeWrapExcludePools() public {
        _giveZrx(safe, 1000 ether);

        bytes32[] memory seedPools = new bytes32[](2);
        seedPools[0] = Constants.TARGET_POOL_31;
        seedPools[1] = Constants.TARGET_POOL_48;
        _safeRunStakeAndDelegate(safe, seedPools, 500 ether);
        _rollEpoch();

        // Exclude pool 31 from the wrap; pool 48 is the source.
        bytes32[] memory exclude = new bytes32[](1);
        exclude[0] = Constants.TARGET_POOL_31;
        LibScript.PlanStep[] memory steps =
            new WrapGovernance().plan("exclude-pools", safe, delegatee, 250 ether, exclude);

        require(steps.length > 1, "empty plan");
        _executeStep(steps[0], safe);
        _rollEpoch();

        for (uint256 i = 1; i < steps.length; i++) {
            _executeStep(steps[i], safe);
        }

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 250 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_48);
        assertEq(bal31.currentEpochBalance, 250 ether, "excluded pool still delegated");
        assertEq(bal48.currentEpochBalance, 0, "source pool undelegated");
    }

    function testSafeWrapMultiDelegate() public {
        _giveZrx(safe, 1000 ether);

        address[] memory delegatees = new address[](3);
        delegatees[0] = vm.addr(10);
        delegatees[1] = vm.addr(11);
        delegatees[2] = vm.addr(12);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether;
        amounts[2] = 100 ether;

        LibScript.PlanStep[] memory steps =
            new WrapGovernanceMultiDelegate().plan(safe, delegatees, amounts);
        _executeSteps(steps, safe);

        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(safe), 700 ether, "ZRX balance");
        assertEq(IERC20(Constants.ZRX_TOKEN).allowance(safe, Constants.WZRX_TOKEN), 0, "allowance reset");

        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(safe, delegatees[i]);
            assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe), amounts[i], "child Safe balance");
            assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(childSafe), delegatees[i], "child Safe delegatee");
        }
    }

    function _executeSteps(LibScript.PlanStep[] memory steps, address sender) internal {
        for (uint256 i = 0; i < steps.length; i++) {
            _executeStep(steps[i], sender);
        }
    }

    function _executeStep(LibScript.PlanStep memory step, address sender) internal {
        vm.prank(sender);
        (bool success, bytes memory returndata) = step.to.call{value: step.value}(step.data);
        if (!success) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }
    }

    function _safeRunStakeAndDelegate(address staker, bytes32[] memory pools, uint256 amount) internal {
        LibScript.PlanStep[] memory steps = new StakeAndDelegate().plan(staker, amount, amount, pools);
        _executeSteps(steps, staker);
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
}
