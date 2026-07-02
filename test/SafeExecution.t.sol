// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ZrxFixture} from "./Fixtures.sol";
import {Constants} from "../src/constants/Constants.sol";
import {RedelegateMode, WrapGovernanceMode} from "../src/types/Types.sol";
import {StakeAndDelegate} from "../script/StakeAndDelegate.s.sol";
import {Redelegate} from "../script/Redelegate.s.sol";
import {WrapGovernance} from "../script/WrapGovernance.s.sol";
import {WrapGovernanceMultiDelegate} from "../script/WrapGovernanceMultiDelegate.s.sol";
import {LibSafeChild} from "../src/libraries/LibSafeChild.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IwZRX} from "../src/interfaces/IwZRX.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

/**
 * @title SafeExecution
 * @notice Verifies that operations work when executed through a real Safe
 *         `execTransaction` using the approved-hash flow. A fresh Safe proxy is
 *         deployed for each run so assertions are independent of mainnet state.
 */
contract SafeExecutionTest is ZrxFixture {
    address internal safe;
    address internal delegatee;
    bytes32[] internal targetPools;
    address[] internal owners;

    StakeAndDelegate internal stakeAndDelegate;
    Redelegate internal redelegate;
    WrapGovernance internal wrapGovernance;
    WrapGovernanceMultiDelegate internal wrapMultiDelegate;

    function setUp() public {
        _createFork();
        delegatee = Constants.OX_LABS_DEPLOYMENT_SAFE;
        targetPools = [Constants.TARGET_POOL_31, Constants.TARGET_POOL_48, Constants.TARGET_POOL_34];

        stakeAndDelegate = new StakeAndDelegate();
        redelegate = new Redelegate();
        wrapGovernance = new WrapGovernance();
        wrapMultiDelegate = new WrapGovernanceMultiDelegate();

        // Deploy a fresh Safe proxy with two deterministic owners and threshold 2.
        owners = new address[](2);
        owners[0] = vm.addr(100);
        owners[1] = vm.addr(101);
        bytes memory initializer = abi.encodeWithSelector(
            ISafe.setup.selector,
            owners,
            2, // threshold
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(address(0))
        );
        safe = ISafeProxyFactory(Constants.SAFE_PROXY_FACTORY).createProxyWithNonce(
            Constants.SAFE_SINGLETON, initializer, 0
        );

    }

    function testSafeStakeAndDelegate() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory pools = new bytes32[](2);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(safe);
        stakeAndDelegate.run(safe, 100 ether, 100 ether, _poolsToCsv(pools));

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

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        stakeAndDelegate.run(safe, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        redelegate.run(RedelegateMode.RedelegateAll, safe, 0, _poolsToCsv(targetPools));

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

        wrapGovernance.run(WrapGovernanceMode.Liquid, safe, delegatee, "");

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 1000 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");
    }

    function testSafeWrapFull() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        stakeAndDelegate.run(safe, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        wrapGovernance.run(WrapGovernanceMode.Full, safe, delegatee, "");

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
        stakeAndDelegate.run(safe, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        bytes32[] memory exclude = new bytes32[](1);
        exclude[0] = Constants.TARGET_POOL_31;

        wrapGovernance.run(WrapGovernanceMode.ExcludePools, safe, delegatee, _poolsToCsv(exclude));

        assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(safe), 250 ether, "wZRX balance");
        assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(safe), delegatee, "delegatee");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        IStakingProxy.StoredBalance memory bal48 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_48);
        assertEq(bal31.currentEpochBalance, 250 ether, "excluded pool still delegated");
        assertEq(bal48.currentEpochBalance, 0, "source pool undelegated");
    }

    function testSafeUndelegateAll() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        stakeAndDelegate.run(safe, 500 ether, 500 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        redelegate.run(RedelegateMode.UndelegateAll, safe, 0, "");

        IStakingProxy.StoredBalance memory bal31 =
            IStakingProxy(Constants.STAKING_PROXY).getStakeDelegatedToPoolByOwner(safe, Constants.TARGET_POOL_31);
        assertEq(bal31.nextEpochBalance, 0, "pool 31 undelegated");
    }

    function testSafeRedelegateAmountConsolidate() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        // Seed a target and a non-target pool, then consolidate all stake into the targets.
        bytes32[] memory seedPools = new bytes32[](2);
        seedPools[0] = Constants.TARGET_POOL_31;
        seedPools[1] = bytes32(uint256(1));
        stakeAndDelegate.run(safe, 800 ether, 800 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        redelegate.run(RedelegateMode.RedelegateAmount, safe, 800 ether, _poolsToCsv(targetPools));

        uint256 total = 0;
        for (uint256 i = 0; i < targetPools.length; i++) {
            total += IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(safe, targetPools[i]).nextEpochBalance;
        }
        assertEq(total, 800 ether, "total target stake");
    }

    function testSafeRedelegateAmountDecrease() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        bytes32[] memory seedPools = new bytes32[](1);
        seedPools[0] = Constants.TARGET_POOL_31;
        stakeAndDelegate.run(safe, 800 ether, 800 ether, _poolsToCsv(seedPools));
        _rollEpoch();

        redelegate.run(RedelegateMode.RedelegateAmount, safe, 500 ether, _poolsToCsv(targetPools));

        uint256 total = 0;
        for (uint256 i = 0; i < targetPools.length; i++) {
            total += IStakingProxy(Constants.STAKING_PROXY)
                .getStakeDelegatedToPoolByOwner(safe, targetPools[i]).nextEpochBalance;
        }
        assertEq(total, 500 ether, "total target stake");
    }

    function testSafeUnstake() public {
        _giveZrx(safe, 1000 ether);
        vm.deal(safe, 10 ether);

        vm.startPrank(safe);
        IERC20(Constants.ZRX_TOKEN).approve(Constants.ERC20_PROXY, 500 ether);
        IStakingProxy(Constants.STAKING_PROXY).stake(500 ether);
        vm.stopPrank();

        uint256 zrxBefore = IERC20(Constants.ZRX_TOKEN).balanceOf(safe);

        wrapGovernance.run(WrapGovernanceMode.Unstake, safe, delegatee, "");

        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(safe) - zrxBefore, 500 ether, "ZRX balance increased");
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

        wrapMultiDelegate.run(safe, delegatees, amounts);

        assertEq(IERC20(Constants.ZRX_TOKEN).balanceOf(safe), 700 ether, "ZRX balance");
        assertEq(IERC20(Constants.ZRX_TOKEN).allowance(safe, Constants.WZRX_TOKEN), 0, "allowance reset");

        for (uint256 i = 0; i < delegatees.length; i++) {
            address childSafe = LibSafeChild.predictChildSafeAddress(safe, delegatees[i]);
            assertEq(IwZRX(Constants.WZRX_TOKEN).balanceOf(childSafe), amounts[i], "child Safe balance");
            assertEq(IwZRX(Constants.WZRX_TOKEN).delegates(childSafe), delegatees[i], "child Safe delegatee");
        }
    }
}
