// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract  BondingCurveUtil {

    using FixedPointMathLib for uint256;

    /**
     * @notice Calculates the number of tokens to mint based on the amount of base currency contributed.
     * @param currentAmount Total base currency already in the pool (scaled to PRECISION).
     * @param deltaAmount Additional base currency contributed (scaled to PRECISION).
     * @param A Curve parameter representing the maximum possible fund amount.
     * @param B Curve scaling factor.
     * @param C Curve offset parameter.
     * @return tokenAmount Number of tokens to mint.
     */
    function getAmountOut(
        uint256 currentAmount ,
        uint256 deltaAmount,
        uint256 A,
        uint256 B,
        uint256 C
    ) public pure returns (uint256 tokenAmount) {
        uint256 newFundAmount = A - B.divWadUp(C + currentAmount + deltaAmount);
        uint256 currentFundAmount = A - B.divWadUp(C + currentAmount);

        require(newFundAmount >= currentFundAmount, "Calculation error");
        tokenAmount = newFundAmount - currentFundAmount;
    }

    /**
     * @notice Calculates the amount of base currency received when selling tokens.
     * @param baseAmount Total base currency currently in the pool (scaled to PRECISION).
     * @param deltaToken Number of tokens being sold (scaled to PRECISION).
     * @param A Curve parameter representing the maximum possible fund amount.
     * @param B Curve scaling factor.
     * @param C Curve offset parameter.
     * @return received Amount of base currency received for selling the tokens.
     */
    function getFundsReceived(
        uint256 baseAmount,
        uint256 deltaToken,
        uint256 A,
        uint256 B,
        uint256 C
    ) public pure returns (uint256 received) {
        uint256 currentFundAmount = A - B.divWadUp(C + baseAmount);
        uint256 newFundAmount = currentFundAmount - deltaToken;
        require(newFundAmount < currentFundAmount, "Invalid token amount");

        uint256 newBaseAmount = B.divWadUp(A - newFundAmount) - C;
        require(baseAmount > newBaseAmount, "Insufficient funds");
        received = baseAmount - newBaseAmount;
    }

    /**
     * @notice Computes the current price of a token in terms of base currency.
     * @param currentAmount Total base currency currently in the pool (scaled to PRECISION).
     * @param A Curve parameter representing the maximum possible fund amount.
     * @param B Curve scaling factor.
     * @param C Curve offset parameter.
     * @return tokenPrice Price of one token in terms of base currency.
     */
    function getCurrentPrice(uint256 currentAmount, uint256 A, uint256 B, uint256 C) public pure returns (uint256 tokenPrice) {
        uint256 numerator = (C + currentAmount).mulWadUp(C + currentAmount);
        tokenPrice = numerator.divWadUp(B);
    }

    /**
     * @notice Computes the price based on the square root price representation used in Uniswap V3.
     * @param sqrtPriceX96 Square root price scaled by 2^96.
     * @return Price in base currency.
     */
    function price(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 p18 = 1e18;
        uint256 sqr18 = p18.sqrt();
        return (sqrtPriceX96 * sqr18 / (2 ** 96)) * (sqrtPriceX96 * sqr18 / (2 ** 96));
    }

    /**
     * @notice Calculates sqrtPriceX96 given two token amounts, used in Uniswap V3 calculations.
     * @param amount0 Amount of token0.
     * @param amount1 Amount of token1.
     * @return sqrtPriceX96 Square root price scaled by 2^96.
     */
    function calculateSqrtPriceX96(uint256 amount0, uint256 amount1) public pure returns (uint160) {
        require(amount0 > 0, "amount0 must be greater than 0");
        require(amount1 > 0, "amount1 must be greater than 0");

        uint256 Q96 = 2 ** 96;
        uint256 ratio = (amount1 * 1e18) / amount0;
        uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(ratio) * Q96 / 1e9;

        require(sqrtPriceX96 <= type(uint160).max, "sqrtPriceX96 overflow");
        return uint160(sqrtPriceX96);
    }
}
