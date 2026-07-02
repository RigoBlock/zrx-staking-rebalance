// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ZrxFixture} from "./Fixtures.sol";
import {Constants} from "../src/constants/Constants.sol";
import {TreasuryMode} from "../src/types/Types.sol";
import {TreasuryMigration} from "../script/TreasuryMigration.s.sol";
import {IZrxTreasury} from "../src/interfaces/IZrxTreasury.sol";

/**
 * @title TreasuryMigrationTest
 * @notice Verifies that treasury migration actions are built from live balances
 *         and that proposal actions are persisted so execute mode can replay them.
 */
contract TreasuryMigrationTest is ZrxFixture {
    TreasuryMigration internal migration;
    address internal proposer;

    function setUp() public {
        _createFork();
        migration = new TreasuryMigration();
        proposer = vm.addr(1);
        vm.createDir("proposals", true);
    }

    function testBuildActions() public {
        _giveZrx(Constants.OLD_ZRX_TREASURY, 500 ether);
        deal(Constants.WCELO_TOKEN, Constants.OLD_ZRX_TREASURY, 200 ether);
        deal(Constants.MATIC_TOKEN, Constants.OLD_ZRX_TREASURY, 300 ether);

        IZrxTreasury.ProposedAction[] memory actions = migration.buildActions();
        assertEq(actions.length, 5, "zrx + wcelo + matic actions");

        assertEq(actions[0].target, Constants.ZRX_TOKEN);
        assertEq(actions[1].target, Constants.WCELO_TOKEN);
        assertEq(actions[2].target, Constants.MATIC_TOKEN);
        assertEq(actions[3].target, Constants.POLYGON_MIGRATION);
        assertEq(actions[4].target, Constants.POL_TOKEN);
    }

    function testProposeAndExecuteRoundTrip() public {
        _giveZrx(Constants.OLD_ZRX_TREASURY, 500 ether);
        deal(Constants.WCELO_TOKEN, Constants.OLD_ZRX_TREASURY, 200 ether);
        deal(Constants.MATIC_TOKEN, Constants.OLD_ZRX_TREASURY, 300 ether);

        address treasury = Constants.OLD_ZRX_TREASURY;

        vm.mockCall(
            treasury,
            abi.encodeWithSelector(IZrxTreasury.proposalThreshold.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            treasury,
            abi.encodeWithSelector(IZrxTreasury.getVotingPower.selector),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            treasury, abi.encodeWithSelector(IZrxTreasury.propose.selector), abi.encode(uint256(1))
        );
        vm.mockCall(
            treasury,
            abi.encodeWithSelector(IZrxTreasury.proposalCount.selector),
            abi.encode(uint256(1))
        );

        migration.run(TreasuryMode.Propose, proposer, "", 0);

        string memory path = "proposals/TreasuryMigration-1.txt";
        assertTrue(vm.exists(path), "actions file persisted");

        IZrxTreasury.ProposedAction[] memory actions = migration.buildActions();
        vm.mockCall(treasury, abi.encodeWithSelector(IZrxTreasury.execute.selector), "");
        vm.expectCall(
            treasury, abi.encodeWithSelector(IZrxTreasury.execute.selector, uint256(1), actions)
        );
        migration.run(TreasuryMode.Execute, proposer, "", 1);
    }
}
