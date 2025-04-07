// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBondingCurve {

    function fundingGoal(address _token) external view  returns (uint256);

    function getCurrentPrice(address tokenAddress) external view  returns (uint256 );

    function getProgress(address tokenAddress)  external view  returns (bool whiteListModel,uint256 raised, uint256 target,uint256 beeCollateral,uint256 beeFunding) ;

    function getState(address tokenAddress) external view  returns (uint8);

    function getCollateral(address tokenAddress) external view  returns (uint256);

    function getTotalTokensAvailable(address tokenAddress) external view  returns (uint256);

    function getFeePercent() external view  returns (uint24 denominator ,uint256 percent);

    function calculateRemainingEthNeeded(address tokenAddress, address user) external view returns (uint256);

    function getEnTime(address tokenAddress) external view returns (uint256);
}
