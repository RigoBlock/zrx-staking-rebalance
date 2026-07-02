// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ZrxFixture} from "./Fixtures.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {RedelegateMode, WrapGovernanceMode} from "../src/types/Types.sol";
import {StakeAndDelegate} from "../script/StakeAndDelegate.s.sol";
import {Redelegate} from "../script/Redelegate.s.sol";
import {WrapGovernance} from "../script/WrapGovernance.s.sol";
import {WrapGovernanceMultiDelegate} from "../script/WrapGovernanceMultiDelegate.s.sol";
import {LibSafeChild} from "../src/libraries/LibSafeChild.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

contract OperationsTest is ZrxFixture {
    address internal staker;
    address internal delegatee;
    bytes32[] internal targetPools;

    function setUp() public {
        _createFork();
        staker = vm.addr(1);
        delegatee = vm.addr(2);
        targetPools = [Constants.TARGET_POOL_31, Constants.TARGET_POOL_48, Constants.TARGET_POOL_34];
    }

    function testStakeAndDelegate() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        bytes32[] memory pools = new bytes32[](2);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;

        new StakeAndDelegate().run(staker, 100 ether, 100 ether, _poolsToCsv(pools));

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_48);

        assertEq(bal31.nextEpochBalance, 50 ether, "pool 31 delegation");
        assertEq(bal48.nextEpochBalance, 50 ether, "pool 48 delegation");
    }

    function testDelegateEqual() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        // Create undelegated stake by staking directly.
        vm.startPrank(staker);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.ERC20_PROXY, 100 ether);
        IStakingProxy(Constants.STAKING_PROXY).stake(100 ether);
        vm.stopPrank();

        bytes32[] memory pools = new bytes32[](2);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;

        // stakeAmount=0, delegateAmount=USE_FULL_BALANCE delegates all undelegated stake.
        new StakeAndDelegate().run(staker, 0, type(uint256).max, _poolsToCsv(pools));

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_48);

        assertEq(bal31.nextEpochBalance, 50 ether, "pool 31 delegation");
        assertEq(bal48.nextEpochBalance, 50 ether, "pool 48 delegation");
    }

    function testRedelegateAll() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        // Seed a single pool with 500 ZRX and roll the epoch so it is active.
        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(staker, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        // Redelegate all active stake across the three target pools.
        new Redelegate().run(RedelegateMode.RedelegateAll, staker, 0, _poolsToCsv(targetPools));

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_48);
        IStakingProxy.StoredBalance memory bal34 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_34);

        assertEq(bal31.nextEpochBalance + bal48.nextEpochBalance + bal34.nextEpochBalance, 500 ether, "total");
        assertGt(bal31.nextEpochBalance, 0, "pool 31");
        assertGt(bal48.nextEpochBalance, 0, "pool 48");
        assertGt(bal34.nextEpochBalance, 0, "pool 34");
    }

    function testWrapLiquid() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        new WrapGovernance().run(WrapGovernanceMode.Liquid, staker, delegatee, "");

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(staker), 1000 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(staker), delegatee, "delegatee");
    }

    function testWrapFull() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(staker, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        new WrapGovernance().run(WrapGovernanceMode.Full, staker, delegatee, "");

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(staker), 500 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(staker), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        assertEq(bal31.currentEpochBalance, 0, "stake undelegated");
    }

    function testWrapExcludePools() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        bytes32[] memory seedPools = new bytes32[](2);
        seedPools[0] = Constants.TARGET_POOL_31;
        seedPools[1] = Constants.TARGET_POOL_48;
        new StakeAndDelegate().run(staker, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        // Exclude pool 31 from the wrap; pool 48 is the source.
        bytes32[] memory exclude = new bytes32[](1);
        exclude[0] = Constants.TARGET_POOL_31;
        new WrapGovernance().run(WrapGovernanceMode.ExcludePools, staker, delegatee, _poolsToCsv(exclude));

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(staker), 250 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(staker), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_48);
        assertEq(bal31.currentEpochBalance, 250 ether, "excluded pool still delegated");
        assertEq(bal48.currentEpochBalance, 0, "source pool undelegated");
    }

    function testWrapMultiDelegate() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        address[] memory delegatees = new address[](3);
        delegatees[0] = vm.addr(10);
        delegatees[1] = vm.addr(11);
        delegatees[2] = vm.addr(12);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether;
        amounts[2] = 100 ether;

        new WrapGovernanceMultiDelegate().run(staker, delegatees, amounts);

        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(staker), 700 ether, "ZRX balance");
        assertEq(IERC20(Constants.ZRX_TOKEN).allowance(staker, Constants.WZRX_TOKEN), 0, "allowance reset");

        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(staker, delegatees[i]);
            assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe), amounts[i], "child Safe balance");
            assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(childSafe), delegatees[i], "child Safe delegatee");
        }
    }

    function testUndelegateAll() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(staker, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        new Redelegate().run(RedelegateMode.UndelegateAll, staker, 0, "");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(staker, Constants.TARGET_POOL_31);
        assertEq(bal31.nextEpochBalance, 0, "pool 31 undelegated");
    }

    function testRedelegateAmountConsolidate() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        // Seed a target and a non-target pool, then consolidate all stake into the targets.
        bytes32[] memory seedPools = new bytes32[](2);
        seedPools[0] = Constants.TARGET_POOL_31;
        seedPools[1] = bytes32(uint256(1));
        new StakeAndDelegate().run(staker, 800 ether, 800 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        new Redelegate().run(RedelegateMode.RedelegateAmount, staker, 800 ether, _poolsToCsv(targetPools));

        uint256 total = 0;
        for (uint256 i = 0; i < targetPools.length; i++) {
            total += IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, targetPools[i]).nextEpochBalance;
        }
        assertEq(total, 800 ether, "total target stake");
    }

    function testRedelegateAmountDecrease() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        new StakeAndDelegate().run(staker, 800 ether, 800 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        new Redelegate().run(RedelegateMode.RedelegateAmount, staker, 500 ether, _poolsToCsv(targetPools));

        uint256 total = 0;
        for (uint256 i = 0; i < targetPools.length; i++) {
            total += IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(staker, targetPools[i]).nextEpochBalance;
        }
        assertEq(total, 500 ether, "total target stake");
    }

    function testUnstake() public {
        _giveZrx(staker, 1000 ether);
        vm.deal(staker, 10 ether);

        // Create undelegated stake by staking directly.
        vm.startPrank(staker);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.ERC20_PROXY, 500 ether);
        IStakingProxy(Constants.STAKING_PROXY).stake(500 ether);
        vm.stopPrank();

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(staker);

        new WrapGovernance().run(WrapGovernanceMode.Unstake, staker, delegatee, "");

        assertEq(
            IERC20(Constants.ZRX_TOKEN).balanceOf(staker) - zrxBefore,
            500 ether,
            "ZRX balance increased"
        );
    }

    function testSplitEqually() public pure {
        uint256[] memory parts = LibStaking.splitEqually(100 ether, 3);
        assertEq(parts[0], 33333333333333333334);
        assertEq(parts[1], 33333333333333333333);
        assertEq(parts[2], 33333333333333333333);
        assertEq(parts[0] + parts[1] + parts[2], 100 ether, "sum");
    }

    function testSplitByWeights() public pure {
        uint256[] memory weights = new uint256[](2);
        weights[0] = 75;
        weights[1] = 25;
        uint256[] memory parts = LibStaking.splitByWeights(100 ether, weights);
        assertEq(parts[0], 75 ether);
        assertEq(parts[1], 25 ether);
    }
}
