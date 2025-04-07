// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardDistributor {

    struct ProductReward {
        uint256 tokensPerInterval;    // Number of tokens distributed per interval (e.g., per second)
        uint256 lastDistributionTime; // Last time rewards were distributed (or calculated)
    }

    function viewRewards() external view returns (address );
    function pendingRewards(uint256 productId) external view returns (uint256 );
    function distribute(uint256 productId) external returns ( uint256  );
    function getProductRewards(uint256) external view returns (ProductReward memory);
    function getUndistributedRewards(uint256 productId) external view  returns (uint256) ;
}
