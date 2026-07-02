// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {Constants} from "../src/constants/Constants.sol";
import {LibStaking} from "../src/libraries/LibStaking.sol";
import {LibSafe} from "../src/libraries/LibSafe.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IPolygonMigration} from "../src/interfaces/IPolygonMigration.sol";
import {IZrxTreasury} from "../src/interfaces/IZrxTreasury.sol";
import {IStakingProxy} from "../src/interfaces/IStakingProxy.sol";
import {TreasuryMode, Call} from "../src/types/Types.sol";

contract TreasuryMigration is Script {
    // Storage array for the single treasury call, keeping the script flat.
    Call[] internal _calls;

    /// @notice Propose or execute the treasury migration.
    /// @param mode Operation mode (propose, execute).
    /// @param proposer Proposer address; pass address(0) to use the default staker.
    /// @param operatedPoolsCsv Comma-separated pool ids used to prove voting power.
    ///                         Empty string uses defaultTargetPools().
    /// @param proposalId Proposal id; only used for execute mode.
    function run(
        TreasuryMode mode,
        address proposer,
        string memory operatedPoolsCsv,
        uint256 proposalId
    ) external {
        if (proposer == address(0)) {
            proposer = Constants.DEFAULT_STAKER;
        }
        require(proposer != address(0), "Invalid proposer");
        bytes32[] memory operatedPoolIds = LibStaking.parsePools(operatedPoolsCsv);

        if (mode == TreasuryMode.Propose) {
            IZrxTreasury.ProposedAction[] memory actions = buildActions();
            require(actions.length > 0, "no actions");

            IZrxTreasury treasury = IZrxTreasury(Constants.OLD_ZRX_TREASURY);
            uint256 threshold = treasury.proposalThreshold();
            uint256 votingPower = treasury.getVotingPower(proposer, operatedPoolIds);
            require(votingPower >= threshold, "voting power below threshold");

            uint256 executionEpoch = IStakingProxy(Constants.STAKING_PROXY).currentEpoch() + 2;

            bytes memory proposeData = abi.encodeWithSelector(
                IZrxTreasury.propose.selector,
                actions,
                executionEpoch,
                "Migrate old ZRX treasury assets to the new 0x governance treasury.",
                operatedPoolIds
            );

            delete _calls;
            _calls.push(Call({target: Constants.OLD_ZRX_TREASURY, value: 0, data: proposeData}));
            bool executed = LibSafe.executeCalls(proposer, _calls);

            if (executed) {
                // Proposal id is not returned from the Safe execTransaction call above, so re-read it.
                uint256 id = IZrxTreasury(Constants.OLD_ZRX_TREASURY).proposalCount();
                _persistActions(id, actions);
                console2.log("Treasury proposal created: %d", id);
            } else {
                console2.log(
                    "Treasury proposal approve phase complete; run execute phase to create"
                );
            }
        } else {
            IZrxTreasury.ProposedAction[] memory actions = _loadActions(proposalId);
            require(actions.length > 0, "no actions loaded for proposal");

            bytes memory executeData =
                abi.encodeWithSelector(IZrxTreasury.execute.selector, proposalId, actions);

            delete _calls;
            _calls.push(Call({target: Constants.OLD_ZRX_TREASURY, value: 0, data: executeData}));
            bool executed = LibSafe.executeCalls(proposer, _calls);

            if (executed) {
                console2.log("Treasury proposal executed");
            } else {
                console2.log(
                    "Treasury proposal approve phase complete; run execute phase to execute"
                );
            }
        }
    }

    function buildActions() public view returns (IZrxTreasury.ProposedAction[] memory actions) {
        uint256 zrx = IERC20(Constants.ZRX_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);
        uint256 wCelo = IERC20(Constants.WCELO_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);
        uint256 matic = IERC20(Constants.MATIC_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);
        uint256 polBefore = IERC20(Constants.POL_TOKEN).balanceOf(Constants.OLD_ZRX_TREASURY);

        uint256 count = 0;
        if (zrx > 0) count++;
        if (wCelo > 0) count++;
        if (matic > 0) count += 3;

        actions = new IZrxTreasury.ProposedAction[](count);
        uint256 idx = 0;

        if (zrx > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.ZRX_TOKEN,
                data: abi.encodeWithSelector(
                    IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, zrx
                ),
                value: 0
            });
            idx++;
        }

        if (wCelo > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.WCELO_TOKEN,
                data: abi.encodeWithSelector(
                    IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, wCelo
                ),
                value: 0
            });
            idx++;
        }

        if (matic > 0) {
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.MATIC_TOKEN,
                data: abi.encodeWithSelector(
                    IERC20.approve.selector, Constants.POLYGON_MIGRATION, matic
                ),
                value: 0
            });
            idx++;
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.POLYGON_MIGRATION,
                data: abi.encodeWithSelector(IPolygonMigration.migrate.selector, matic),
                value: 0
            });
            idx++;
            // Transfer the migrated MATIC plus any POL already held by the treasury.
            uint256 polToTransfer = polBefore + matic;
            actions[idx] = IZrxTreasury.ProposedAction({
                target: Constants.POL_TOKEN,
                data: abi.encodeWithSelector(
                    IERC20.transfer.selector, Constants.NEW_ZRX_TREASURY, polToTransfer
                ),
                value: 0
            });
            idx++;
        }
    }

    // forge-lint: disable-next-item(unsafe-cheatcode)
    // Intentional filesystem write: the exact ProposedAction[] used at propose
    // time must be replayed verbatim at execute time to avoid the actions-hash
    // mismatch bug. Scope is restricted by foundry.toml fs_permissions.
    function _persistActions(uint256 proposalId, IZrxTreasury.ProposedAction[] memory actions)
        private
    {
        bytes memory data = abi.encode(proposalId, actions);
        string memory path = _proposalFilePath(proposalId);
        vm.writeFile(path, vm.toString(data));
        console2.log("Proposal actions persisted to: %s", path);
    }

    // forge-lint: disable-next-item(unsafe-cheatcode)
    // Reads the actions persisted by the propose step (see _persistActions).
    // Scope is restricted by foundry.toml fs_permissions.
    function _loadActions(uint256 proposalId)
        private
        view
        returns (IZrxTreasury.ProposedAction[] memory actions)
    {
        string memory path = _proposalFilePath(proposalId);
        string memory hexString = vm.readFile(path);
        bytes memory data = vm.parseBytes(hexString);
        (, actions) = abi.decode(data, (uint256, IZrxTreasury.ProposedAction[]));
    }

    function _proposalFilePath(uint256 proposalId) private pure returns (string memory) {
        return string.concat("proposals/TreasuryMigration-", vm.toString(proposalId), ".txt");
    }
}
