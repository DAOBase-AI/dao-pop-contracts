// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract BondingCurveUtil {

    using FixedPointMathLib for uint256;

    uint256 public constant A = 1126650200* 1e18;
    uint256 public constant B = 1239315220* 1e18;
    uint256 public constant C = 11 * 1e17;

    constructor() {

    }

    /**
     * @notice Calculate the number of tokens to mint for a given amount of ETH/sol contributed
     * @param ethAmount Amount of ETH/sol contributed (scaled to PRECISION)
     * @param currentEth Total ETH/sol already contributed to the pool (scaled to PRECISION)
     * @return tokenAmount Number of tokens to mint
     */
    function getAmountOut(
        uint256 currentEth ,
        uint256 ethAmount
    ) public pure returns (uint256 tokenAmount) {
        // Calculate y (new fund amount): y = A - B / (C + currentEth + ethAmount)
        uint256 newFundAmount = A - B.divWadUp(C + currentEth + ethAmount) ;
        uint256 currentFundAmount = A-  B.divWadUp(C + currentEth );

        // tokenAmount is the difference in fund values before and after adding ethAmount
        require(newFundAmount >= currentFundAmount, "Calculation error");
        tokenAmount = newFundAmount - currentFundAmount ;
    }

    /**
     * @notice Calculate the funds received for selling tokens
     * @param currentEth Total ETH/sol already contributed to the pool (scaled to PRECISION)
     * @param deltaToken Amount of tokens being sold (scaled to PRECISION)
     * @return ethReceived Amount of ETH/sol received for selling the tokens
     */
    function getFundsReceived(
        uint256 currentEth,
        uint256 deltaToken
    ) public pure returns (uint256 ethReceived) {

        // Calculate the current y (funds): y = A - B / (C + currentEth)
        uint256 currentFundAmount = A - B.divWadUp(C + currentEth);

        // Calculate new y after selling deltaToken: newFundAmount = currentFundAmount - deltaToken
        uint256 newFundAmount = currentFundAmount - deltaToken;
        require(newFundAmount < currentFundAmount, "Invalid token amount");

        // Reverse the bonding curve to calculate new eth amount: x = B / (A - y) - C
        uint256 newEth = B.divWadUp(A - newFundAmount) - C;

        // ethReceived is the difference between the currentEth and newEth
        require(currentEth > newEth, "Insufficient funds");
        ethReceived = currentEth - newEth;
    }

    /**
   * @notice Calculate the current price of a token (ETH per token)
     * @param currentEth Total ETH/sol already contributed to the pool (scaled to PRECISION)
     * @return tokenPrice The price of 1 token in ETH
     */
    function getCurrentPrice(uint256 currentEth) public pure returns (uint256 tokenPrice) {
        // Price of token is derived from the bonding curve formula: p(x) = (C + x)^2/B
        // where x is the current ETH amount in the pool (currentEth)
        uint256 numerator = (C + currentEth).mulWadUp(C + currentEth);  // (C + x)^2
        tokenPrice = numerator.divWadUp(B);// (C + x)^2 / B
    }

    function price(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 p18 = 1e18;
        uint256 sqr18 = p18.sqrt();
        // Convert sqrtPrice to sqrtPriceX96 by multiplying by 2^96
        return ( sqrtPriceX96 * sqr18/(2 ** 96)) * ( sqrtPriceX96 * sqr18/(2 ** 96)) ;

    }
}
