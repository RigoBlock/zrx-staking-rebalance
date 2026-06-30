// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ZrxFixture} from "./Fixtures.sol";
import {Constants} from "../src/constants/Constants.sol";
import {StakeAndDelegate} from "../script/StakeAndDelegate.s.sol";
import {Redelegate} from "../script/Redelegate.s.sol";
import {WrapGovernance} from "../script/WrapGovernance.s.sol";
import {WrapGovernanceMultiDelegate} from "../script/WrapGovernanceMultiDelegate.s.sol";
import {LibSafeChild} from "../src/libraries/LibSafeChild.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

/**
 * @title SafeExecution
 * @notice Verifies that operations work when executed from the default Safe address.
 */
contract SafeExecutionTest is ZrxFixture {
    address internal safe;
    address internal delegatee;
    bytes32[] internal targetPools;

    function setUp() public {
        _createFork();
        safe = Constants.OX_LABS_DEPLOYMENT_SAFE;
        delegatee = vm.addr(2);
        targetPools = [Constants.TARGET_POOL_31, Constants.TARGET_POOL_48, Constants.TARGET_POOL_34];
    }

    function testSafeStakeAndDelegate() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory pools = new bytes32[](2);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(safe);
        new StakeAndDelegate().run(safe, 100 ether, 100 ether, pools);

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
        vm.deal(safe, 10 ether);

        // Seed a single pool and roll the epoch so the delegation is active.
        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(safe, 500 ether, 500 ether, seedPools);
        _rollEpoch();

        new Redelegate().run("redelegate-all", safe, 0, targetPools);

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
        vm.deal(safe, 10 ether);

        bytes32[] memory empty = new bytes32[](0);
        new WrapGovernance().run("liquid", safe, delegatee, 50 ether, empty);

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 50 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");
    }

    function testSafeWrapFull() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(safe, 500 ether, 500 ether, seedPools);
        _rollEpoch();

        bytes32[] memory empty = new bytes32[](0);
        new WrapGovernance().run("full", safe, delegatee, 500 ether, empty);

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 500 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        assertEq(bal31.currentEpochBalance, 0, "stake undelegated");
    }

    function testSafeWrapExcludePools() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory seedPools = new bytes32[](2);
        seedPools[0] = Constants.TARGET_POOL_31;
        seedPools[1] = Constants.TARGET_POOL_48;
        new StakeAndDelegate().run(safe, 500 ether, 500 ether, seedPools);
        _rollEpoch();

        // Exclude pool 31 from the wrap; pool 48 is the source.
        bytes32[] memory exclude = new bytes32[](1);
        exclude[0] = Constants.TARGET_POOL_31;
        new WrapGovernance().run("exclude-pools", safe, delegatee, 250 ether, exclude);

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
        vm.deal(safe, 10 ether);

        address[] memory delegatees = new address[](3);
        delegatees[0] = vm.addr(10);
        delegatees[1] = vm.addr(11);
        delegatees[2] = vm.addr(12);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether;
        amounts[2] = 100 ether;

        new WrapGovernanceMultiDelegate().run(safe, delegatees, amounts);

        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(safe), 700 ether, "ZRX balance");
        assertEq(IERC20(Constants.ZRX_TOKEN).allowance(safe, Constants.WZRX_TOKEN), 0, "allowance reset");

        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(safe, delegatees[i]);
            assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe), amounts[i], "child Safe balance");
            assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(childSafe), delegatees[i], "child Safe delegatee");
        }
    }
}
