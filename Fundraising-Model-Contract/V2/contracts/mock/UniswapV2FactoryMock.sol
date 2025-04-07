// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import  "./MockPair.sol";

contract UniswapV2FactoryMock {
    address public owner;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "UniswapV2FactoryMock: NOT_OWNER");
        _;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external  returns (address pair) {
        require(tokenA != tokenB, "UniswapV2FactoryMock: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "UniswapV2FactoryMock: ZERO_ADDRESS");
        require(getPair[tokenA][tokenB] == address(0), "UniswapV2FactoryMock: PAIR_EXISTS");

        // Deploy a new MockPair
        MockPair newPair = new MockPair(tokenA, tokenB);
        pair = address(newPair);

        // Update mappings and arrays
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair; // Ensure reverse lookup works
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }
}
