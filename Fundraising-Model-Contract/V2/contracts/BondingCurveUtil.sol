// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

import {TickMath} from "./lib/TickMath.sol";

contract BondingCurveUtil {

    using FixedPointMathLib for uint256;

    uint256 public constant PRECISION = 1e18; // Define precision factor
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = 887272;
    int24 internal constant MIN_TICK = -887272;

    constructor() {}

    /**
     * @notice Calculate the price of one token based on the total base asset in the pool
     * @param totalBaseAmount The total amount of base asset contributed to the pool
     * @param totalTokenAmount The total number of tokens in the pool
     * @return tokenPrice The price of 1 token in terms of the base asset
     */
    function getCurrentPrice(uint256 totalBaseAmount, uint256 totalTokenAmount) public pure returns (uint256 tokenPrice) {
        tokenPrice = totalBaseAmount * PRECISION / totalTokenAmount;
    }

    /**
     * @notice Calculate the price of the base asset in terms of the token
     * @param totalBaseAmount The total amount of base asset in the pool
     * @param totalTokenAmount The total number of tokens in the pool
     * @return tokenPrice The price of the base asset in terms of tokens
     */
    function getBasePrice(uint256 totalBaseAmount, uint256 totalTokenAmount) public pure returns (uint256 tokenPrice) {
        tokenPrice = totalTokenAmount * PRECISION / totalBaseAmount;
    }

    /**
     * @notice Calculate the number of tokens to mint for a given amount of base asset contributed
     * @param totalBaseAmount The total base asset already contributed to the pool
     * @param totalTokenAmount The total number of tokens in the pool
     * @param deltaAmount The amount of base asset being contributed
     * @return tokenAmount The number of tokens to mint
     */
    function getAmountOut(
        uint256 totalBaseAmount,
        uint256 totalTokenAmount,
        uint256 deltaAmount
    ) public pure returns (uint256 tokenAmount) {
        uint256 tokenPrice = getCurrentPrice(totalBaseAmount, totalTokenAmount);
        tokenAmount = (deltaAmount * PRECISION) / tokenPrice;
    }

    /**
     * @notice Calculate the amount of base asset received from selling tokens
     * @param totalBaseAmount The total base asset in the pool
     * @param totalTokenAmount The total number of tokens in the pool
     * @param deltaAmount The number of tokens being sold
     * @return baseReceived The amount of base asset received from selling the tokens
     */
    function getFundsReceived(
        uint256 totalBaseAmount,
        uint256 totalTokenAmount,
        uint256 deltaAmount
    ) public pure returns (uint256 baseReceived) {
        uint256 tokenPrice = getCurrentPrice(totalBaseAmount, totalTokenAmount);
        baseReceived = deltaAmount * tokenPrice / PRECISION;
    }

    function price(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 p18 = 1e18;
        uint256 sqr18 = p18.sqrt();
        return ( sqrtPriceX96 * sqr18 / (2 ** 96)) * ( sqrtPriceX96 * sqr18 / (2 ** 96));
    }

    function calculateSqrtPriceX96(uint256 amount0, uint256 amount1) public pure returns (uint160) {
        require(amount0 > 0, "amount0 must be greater than 0");
        require(amount1 > 0, "amount1 must be greater than 0");

        uint256 Q96 = 2 ** 96;
        uint256 ratio = (amount1 * PRECISION) / amount0;
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(ratio) * Q96 / 1e9;
        require(sqrtPriceX96 <= type(uint160).max, "sqrtPriceX96 overflow");
        return uint160(sqrtPriceX96);
    }

    function getTick(address _tokenAddress, address _baseToken, uint160 sqrtPriceX96, int24 tickSpacing) external pure returns (int24 _tickLower, int24 _tickUpper) {
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        if (tick % tickSpacing != 0) {
            tick = (tick / tickSpacing) * tickSpacing;
        }
        if (_tokenAddress < _baseToken) {
            _tickLower = tick;
            _tickUpper = maxUsableTick(tickSpacing);
        } else {
            _tickLower = minUsableTick(tickSpacing);
            _tickUpper = tick;
        }
    }

    function minUsableTick(int24 tickSpacing) public pure returns (int24) {
        unchecked {
            return (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    function maxUsableTick(int24 tickSpacing) public pure returns (int24) {
        unchecked {
            return (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
}
