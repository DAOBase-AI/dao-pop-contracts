// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILocker {
    function add(address token,uint256 tokenId,address tokenCreator) external;
}

