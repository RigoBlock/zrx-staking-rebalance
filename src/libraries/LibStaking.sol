// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStakingProxy} from "../interfaces/IStakingProxy.sol";
import {Constants} from "../constants/Constants.sol";
import {Delegation} from "../types/Types.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";

library LibStaking {
    uint8 internal constant UNDELEGATED = 0;
    uint8 internal constant DELEGATED = 1;

    // Safety guard: if the staking contract ever grows beyond this many pools,
    // the script aborts rather than silently burning gas on a huge enumeration.
    // Raise this constant if the 0x staking system legitimately adds more pools.
    uint256 internal constant MAX_POOL_ID = 100;

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getActiveDelegations(address stakingProxy, address staker)
        internal
        view
        returns (Delegation[] memory delegations, uint256 total)
    {
        return _getDelegations(stakingProxy, staker, true);
    }

    function getScheduledDelegations(address stakingProxy, address staker)
        internal
        view
        returns (Delegation[] memory delegations, uint256 total)
    {
        return _getDelegations(stakingProxy, staker, false);
    }

    function _getDelegations(address stakingProxy, address staker, bool useCurrent)
        private
        view
        returns (Delegation[] memory delegations, uint256 total)
    {
        IStakingProxy stake = IStakingProxy(stakingProxy);
        uint256 lastPoolId_ = uint256(stake.lastPoolId());
        require(lastPoolId_ <= MAX_POOL_ID, "LibStaking: too many pools; raise MAX_POOL_ID");

        // First count non-zero delegations.
        uint256 count = 0;
        for (uint256 i = 1; i <= lastPoolId_; i++) {
            bytes32 poolId = bytes32(i);
            IStakingProxy.StoredBalance memory bal = stake.getStakeDelegatedToPoolByOwner(staker, poolId);
            uint256 amount = useCurrent ? bal.currentEpochBalance : bal.nextEpochBalance;
            if (amount > 0) {
                count++;
                total += amount;
            }
        }

        delegations = new Delegation[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= lastPoolId_; i++) {
            bytes32 poolId = bytes32(i);
            IStakingProxy.StoredBalance memory bal = stake.getStakeDelegatedToPoolByOwner(staker, poolId);
            uint256 amount = useCurrent ? bal.currentEpochBalance : bal.nextEpochBalance;
            if (amount > 0) {
                delegations[idx] = Delegation({poolId: poolId, amount: amount});
                idx++;
            }
        }
    }

    function encodeMoveStake(bytes32 fromPool, bytes32 toPool, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        bool fromDelegated = fromPool != bytes32(0);
        bool toDelegated = toPool != bytes32(0);
        IStakingProxy.StakeInfo memory from =
            IStakingProxy.StakeInfo(fromDelegated ? DELEGATED : UNDELEGATED, fromPool);
        IStakingProxy.StakeInfo memory to = IStakingProxy.StakeInfo(toDelegated ? DELEGATED : UNDELEGATED, toPool);
        return abi.encodeWithSelector(IStakingProxy.moveStake.selector, from, to, amount);
    }

    function encodeDelegate(bytes32 poolId, uint256 amount) internal pure returns (bytes memory) {
        return encodeMoveStake(bytes32(0), poolId, amount);
    }

    function encodeUndelegate(bytes32 poolId, uint256 amount) internal pure returns (bytes memory) {
        return encodeMoveStake(poolId, bytes32(0), amount);
    }

    function splitByWeights(uint256 total, uint256[] memory weights)
        internal
        pure
        returns (uint256[] memory parts)
    {
        require(weights.length > 0, "empty weights");
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "zero weight");
        parts = new uint256[](weights.length);
        uint256 distributed = 0;
        for (uint256 i = 0; i < weights.length - 1; i++) {
            parts[i] = (total * weights[i]) / totalWeight;
            distributed += parts[i];
        }
        parts[weights.length - 1] = total - distributed;
    }

    function defaultTargetPools() internal pure returns (bytes32[] memory pools) {
        pools = new bytes32[](3);
        pools[0] = Constants.TARGET_POOL_31;
        pools[1] = Constants.TARGET_POOL_48;
        pools[2] = Constants.TARGET_POOL_34;
    }

    /// @notice Parse a comma-separated list of pool ids. Empty string returns the default target pools.
    function parsePools(string memory poolsCsv) internal pure returns (bytes32[] memory pools) {
        if (bytes(poolsCsv).length == 0) return defaultTargetPools();
        string[] memory parts = VM.split(poolsCsv, ",");
        pools = new bytes32[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            pools[i] = VM.parseBytes32(VM.trim(parts[i]));
        }
    }

    function splitEqually(uint256 amount, uint256 count) internal pure returns (uint256[] memory parts) {
        require(count > 0, "zero count");
        parts = new uint256[](count);
        uint256 base = amount / count;
        uint256 remainder = amount - base * count;
        for (uint256 i = 0; i < count; i++) {
            parts[i] = base + (i < remainder ? 1 : 0);
        }
    }
}
