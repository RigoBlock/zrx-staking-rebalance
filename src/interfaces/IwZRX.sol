// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IwZRX {
    function depositFor(address account, uint256 amount) external returns (bool);
    function delegate(address delegatee) external;
    function balanceOf(address account) external view returns (uint256);
    function delegates(address account) external view returns (address);
}
