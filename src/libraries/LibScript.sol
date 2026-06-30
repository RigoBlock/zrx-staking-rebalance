// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

library LibScript {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct PlanStep {
        address to;
        uint256 value;
        bytes data;
        string description;
    }

    function emitPlanJson(PlanStep[] memory steps) internal pure {
        string memory json = _buildPlanJson(steps);
        console2.log("---PLAN_JSON_START---");
        console2.log(json);
        console2.log("---PLAN_JSON_END---");
    }

    function _buildPlanJson(PlanStep[] memory steps) private pure returns (string memory json) {
        json = "[";
        for (uint256 i = 0; i < steps.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                "{",
                "\"to\":\"", VM.toString(steps[i].to), "\","
                "\"value\":\"", VM.toString(steps[i].value), "\","
                "\"data\":\"", VM.toString(steps[i].data), "\","
                "\"description\":\"", steps[i].description, "\""
                "}"
            );
        }
        json = string.concat(json, "]");
    }

}
