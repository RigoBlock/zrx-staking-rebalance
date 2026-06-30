// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IPolygonMigration} from "../src/interfaces/IPolygonMigration.sol";
import {IZrxTreasury} from "../src/interfaces/IZrxTreasury.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";

contract TreasuryMigration is Script {
    enum Mode {
        Propose,
        Execute
    }

    /// @notice Run using the default proposer and default operated pools.
    function run(uint8 mode) external {
        _run(_validateMode(mode), Constants.DEFAULT_STAKER, LibStaking.defaultTargetPools(), 0);
    }

    /// @notice Execute a specific proposal using the default proposer and pools.
    function run(uint8 mode, uint256 proposalId) external {
        _run(_validateMode(mode), Constants.DEFAULT_STAKER, LibStaking.defaultTargetPools(), proposalId);
    }

    /// @notice Run with explicit proposer and pools (used by tests).
    function run(
        uint8 mode,
        address proposer,
        bytes32[] calldata operatedPoolIds,
        uint256 proposalId
    ) external {
        _run(_validateMode(mode), proposer, operatedPoolIds, proposalId);
    }

    function _run(uint8 mode, address proposer, bytes32[] memory operatedPoolIds, uint256 proposalId)
        private
    {
        IZrxTreasury.ProposedAction[] memory actions = buildActions();
        require(actions.length > 0, "no actions");

        if (mode == uint8(Mode.Propose)) {
            IZrxTreasury treasury = IZrxTreasury(Constants.OLD_ZRX_TREASURY);
            uint256 threshold = treasury.proposalThreshold();
            uint256 votingPower = treasury.getVotingPower(proposer, operatedPoolIds);
            require(votingPower >= threshold, "voting power below threshold");

            uint256 executionEpoch = IStakingProxy(Constants.STAKING_PROXY).currentEpoch() + 2;

            vm.startBroadcast(proposer);
            uint256 id = treasury.propose(
                actions,
                executionEpoch,
                "Migrate old ZRX treasury assets to the new 0x governance treasury.",
                operatedPoolIds
            );
            vm.stopBroadcast();

            console2.log("Treasury proposal created: %d", id);
        } else {
            vm.startBroadcast(proposer);
            IZrxTreasury(Constants.OLD_ZRX_TREASURY).execute(proposalId, actions);
            vm.stopBroadcast();
            console2.log("Treasury proposal executed");
        }
    }

    function _validateMode(uint8 mode) private pure returns (uint8) {
        require(mode <= uint8(Mode.Execute), "invalid mode");
        return mode;
    }

    function buildActions() private view returns (IZrxTreasury.ProposedAction[] memory actions) {
        uint256 zrx = IERC20(Constants.ZRX_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);
        uint256 wCelo = IERC20(Constants.WCELO_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);
        uint256 matic = IERC20(Constants.MATIC_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);

        uint256 count = 0;
        if (zrx > 0) count++;
        if (wCelo > 0) count++;
        if (matic > 0) count += 3;

        actions = new IZrxTreasury.ProposedAction[](count);
        uint256 idx = 0;

        if (zrx > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.ZRX_TOKEN,
                data: abi.encodeWithSelector(IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, zrx),
                value: 0
            });
            idx++;
        }

        if (wCelo > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.WCELO_TOKEN,
                data: abi.encodeWithSelector(IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, wCelo),
                value: 0
            });
            idx++;
        }

        if (matic > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.MATIC_TOKEN,
                data: abi.encodeWithSelector(IERC20.approve.selector, Constants.POLYGON_MIGRATION, matic),
                value: 0
            });
            idx++;
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.POLYGON_MIGRATION,
                data: abi.encodeWithSelector(IPolygonMigration.migrate.selector, matic),
                value: 0
            });
            idx++;
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.POL_TOKEN,
                data: abi.encodeWithSelector(IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, matic),
                value: 0
            });
            idx++;
        }
    }
}
