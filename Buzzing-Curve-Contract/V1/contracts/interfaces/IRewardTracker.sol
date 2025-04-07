// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IRewardTracker {
    function stakedAmounts(address _account) external view returns (uint256);
    function updateRewards() external;
    function stake( uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function claim(address _receiver) external returns (uint256 );
    function claimable(address _account) external view returns (uint256  );
    function averageStakedAmounts(address _account) external view returns (uint256);
    function cumulativeRewards(address _account) external view returns (uint256);
}
