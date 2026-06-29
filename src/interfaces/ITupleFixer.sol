// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITupleFixer {
    function encodeUndelegateAll() external view returns (uint256 totalUndelegatedAmount, bytes[] memory encodedCalls);
}
