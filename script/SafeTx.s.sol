// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ISafe} from "../src/interfaces/ISafe.sol";

/**
 * Build a Safe transaction payload and compute its hash.
 *
 * The caller supplies the target nonce so multiple transactions can be proposed
 * in sequence without re-reading on-chain state between calls.
 */
contract SafeTx is Script {
    function run(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 nonce
    ) external view {
        ISafe safeContract = ISafe(safe);
        uint256 threshold = safeContract.getThreshold();
        address[] memory owners = safeContract.getOwners();

        bytes32 txHash = _getTransactionHash(safe, to, value, data, operation, nonce);
        bytes memory execTx = _encodeExecTransaction(to, value, data, operation);
        string memory ownersJson = _ownersToJson(owners);

        _emitJson(safe, to, value, data, operation, nonce, threshold, ownersJson, txHash, execTx);
    }

    function _getTransactionHash(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 nonce
    ) internal view returns (bytes32) {
        return ISafe(safe).getTransactionHash(
            to,
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );
    }

    function _encodeExecTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ISafe.execTransaction.selector,
            to,
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "" // signatures placeholder
        );
    }

    function _emitJson(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 nonce,
        uint256 threshold,
        string memory ownersJson,
        bytes32 txHash,
        bytes memory execTx
    ) internal pure {
        string memory result = "{\n";
        result = string.concat(result, "  \"safe\": \"", vm.toString(safe), "\",\n");
        result = string.concat(result, "  \"to\": \"", vm.toString(to), "\",\n");
        result = string.concat(result, "  \"value\": \"", vm.toString(value), "\",\n");
        result = string.concat(result, "  \"data\": \"", vm.toString(data), "\",\n");
        result = string.concat(result, "  \"operation\": ", vm.toString(operation), ",\n");
        result = string.concat(result, "  \"nonce\": \"", vm.toString(nonce), "\",\n");
        result = string.concat(result, "  \"threshold\": \"", vm.toString(threshold), "\",\n");
        result = string.concat(result, "  \"owners\": ", ownersJson, ",\n");
        result = string.concat(result, "  \"safeTxHash\": \"", vm.toString(txHash), "\",\n");
        result = string.concat(result, "  \"execTransactionCalldata\": \"", vm.toString(execTx), "\"\n");
        result = string.concat(result, "}");
        console2.log("---SAFE_TX_JSON_START---");
        console2.log(result);
        console2.log("---SAFE_TX_JSON_END---");
    }

    function _ownersToJson(address[] memory owners) internal pure returns (string memory json) {
        json = "[";
        for (uint256 i = 0; i < owners.length; i++) {
            json = string.concat(json, i == 0 ? "" : ",", vm.toString(owners[i]));
        }
        json = string.concat(json, "]");
    }
}
