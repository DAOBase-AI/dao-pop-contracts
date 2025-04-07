// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IRewardTracker {
    struct Product {
        uint256 productId;
        uint256 totalStakeAmount;
        uint256 cumulativeRewardPerToken;
        address stakeToken;
        bool isActive;
        uint256 stakeStartTime;
        uint256 stakeEndTime;
        uint256 rewardStartTime;
        uint256 rewardEndTime;
    }

    function stakedAmounts(uint256 _productId,address _account) external view returns (uint256);
    function updateRewards(uint256 _productId) external;
    function stake( uint256 _productId,uint256 _amount) external;
    function unstake(uint256 _productId,uint256 _amount) external;
    function claim(uint256 _productId,address _receiver) external returns (uint256 );
    function claimable(uint256 _productId,address _account) external view returns (uint256  );
    function averageStakedAmounts(uint256 _productId,address _account) external view returns (uint256);
    function cumulativeRewards(uint256 _productId,address _account) external view returns (uint256);
    function getProduct(uint256 _productId) external view returns (Product memory);
    function stakerCount(uint256 _productId) external view returns (uint256 );
}
