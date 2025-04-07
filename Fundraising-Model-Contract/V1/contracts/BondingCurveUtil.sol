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
     * @notice Calculate the price of one token based on the total ETH in the pool
     * @param totalEthAmount The total amount of ETH contributed to the pool (externally passed)
     * @return tokenPrice The price of 1 token in ETH
     */
    function getCurrentPrice(uint256 totalEthAmount,uint256 totalTokenAmount) public pure returns (uint256 tokenPrice) {
        // Price of token is determined by totalEthAmount / SCALE_FACTOR
        tokenPrice = totalEthAmount * PRECISION / totalTokenAmount;
    }

    /**
     * @notice Calculate the price of one token based on the total ETH in the pool
     * @param totalEthAmount The total amount of ETH contributed to the pool (externally passed)
     * @return tokenPrice The price of 1 token in ETH
     */
    function getEthPrice(uint256 totalEthAmount,uint256 totalTokenAmount) public pure returns (uint256 tokenPrice) {
        // Price of token is determined by totalEthAmount / SCALE_FACTOR
        tokenPrice = totalTokenAmount * PRECISION / totalEthAmount;
    }
    /**
     * @notice Calculate the number of tokens to mint for a given amount of ETH contributed
     * @param totalEthAmount The total ETH already contributed to the pool (externally passed)
     * @param ethAmount The amount of ETH being contributed (scaled to precision)
     * @return tokenAmount The number of tokens to mint
     */
    function getAmountOut(
        uint256 totalEthAmount,
        uint256 totalTokenAmount,
        uint256 ethAmount
    ) public pure returns (uint256 tokenAmount) {
        // Calculate the number of tokens based on the current ETH price
        uint256 tokenPrice = getCurrentPrice(totalEthAmount,totalTokenAmount);
        tokenAmount = (ethAmount * PRECISION) / tokenPrice;
        // Use current price to calculate tokens minted
    }

    /**
     * @notice Calculate the ETH received from selling tokens
     * @param totalEthAmount The total ETH already contributed to the pool (externally passed)
     * @param deltaToken The number of tokens being sold
     * @return ethReceived The amount of ETH received from selling the tokens
     */
    function getFundsReceived(
        uint256 totalEthAmount,
        uint256 totalTokenAmount,
        uint256 deltaToken
    ) public pure returns (uint256 ethReceived) {
        uint256 tokenPrice = getCurrentPrice(totalEthAmount,totalTokenAmount);
        ethReceived = deltaToken * tokenPrice/PRECISION; // Use current price to calculate ETH received
    }

    function price(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 p18 = 1e18;
        uint256 sqr18 = p18.sqrt();
        // Convert sqrtPrice to sqrtPriceX96 by multiplying by 2^96
        return ( sqrtPriceX96 * sqr18/(2 ** 96)) * ( sqrtPriceX96 * sqr18/(2 ** 96)) ;

    }


    function calculateSqrtPriceX96(uint256 amount0, uint256 amount1) public pure returns (uint160) {
        require(amount0 > 0, "amount0 must be greater than 0");
        require(amount1 > 0, "amount1 must be greater than 0");

        // Q96 = 2 ** 96
        uint256 Q96 = 2 ** 96;

        // Calculate the ratio = amount1 / amount0
        uint256 ratio = (amount1 * PRECISION) / amount0;

        // Compute sqrtPriceX96 = Q96 * sqrt(ratio)
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(ratio) * Q96 / 1e9;

        // Ensure result fits within uint160
        require(sqrtPriceX96 <= type(uint160).max, "sqrtPriceX96 overflow");

        return uint160(sqrtPriceX96);
    }

    function getTick(address _tokenAddress,address _weth,uint160 sqrtPriceX96,int24 tickSpacing) external pure returns (int24 _tickLower,int24 _tickUpper){
        int24 tick =  TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        if(tick % tickSpacing != 0){
            tick = (tick / tickSpacing) * tickSpacing;
        }

        if(_tokenAddress < _weth){
            _tickLower = tick;
            _tickUpper = maxUsableTick(tickSpacing);
        }else{
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
