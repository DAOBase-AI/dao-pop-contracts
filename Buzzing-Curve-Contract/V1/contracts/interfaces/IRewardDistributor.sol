// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardDistributor {

    function viewRewards() external view returns (address );
    function pendingRewards() external view returns (uint256 );
    function distribute() external returns ( uint256  );
}
