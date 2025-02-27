// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBondingCurve {

    function fundingGoal() external view  returns (uint256);

    function getCurrentPrice(address tokenAddress) external view  returns (uint256 );

    function getProgress(address tokenAddress)  external view  returns (uint256 current, uint256 target) ;

    function getState(address tokenAddress) external view  returns (uint8);

    function getCollateral(address tokenAddress) external view  returns (uint256);

    function getTotalTokensAvailable(address tokenAddress) external view  returns (uint256);

    function getFeePercent() external view  returns (uint24 denominator ,uint256 percent);

}
