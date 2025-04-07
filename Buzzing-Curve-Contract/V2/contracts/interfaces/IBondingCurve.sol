// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBondingCurve {
    enum TokenState {
        NOT_CREATED,
        FUNDING,
        TRADING
    }
    struct AddLiquidityParam {
        address token0 ;
        address token1 ;
        uint256 amount0 ;
        uint256 amount1 ;
        uint160 sqrtPriceX96 ;
        uint24 fee ;
    }

    struct CreatePoolParam {
        address token0 ;
        address token1 ;
        uint160 sqrtPriceX96 ;
        uint24 fee ;
    }

    struct BondingCurveParam {
        uint256 maxSupply ;
        uint256 fundingSupply ;
        uint256 initialSupply ;
        uint256 fundingGoal ;
        uint256 creationFee ;
        uint256 liquidityFee ;
        uint256 creatorReward ;
        uint256 referralFeePercent;
        uint256 feePercent;
        uint256 A;
        uint256 B;
        uint256 C;
    }
    // Events
    event TokenCreated (address indexed user,address indexed token,string symbol,string name,uint256 creationFee,uint256 initialBuyAmount,uint256 timestamp, string businessKey, uint256 daoId);
    event TokenBought(address indexed buyer, address indexed tokenAddress, uint256 amountIn, uint256 amountOut, uint256 fee,uint256 timestamp);
    event TokenSold(address indexed seller, address indexed tokenAddress, uint256 amountIn, uint256 amountOut,uint256 fee,uint256 timestamp);
    event TreasuryUpdated(address newTreasury);
    event FeeTransferred(address indexed payer, address indexed treasury, uint256 feeAmount, uint256 timestamp);
    event ReferralRewardPaid(address indexed user,address indexed referrer, uint256 rewardAmount, uint256 timestamp);

    event TokenLiquidityAdded(
        address indexed token,  // Token address of the liquidity pool
        uint256 amount0,        // Amount of token0 added to the liquidity pool
        uint256 amount1,        // Amount of token1 added to the liquidity pool
        uint160 sqrtPriceX96,   // Initial price of the pool (square root of price)
        uint24 fee,             // Fee percentage for the liquidity pool
        uint256 timestamp       // Timestamp when the liquidity was added
    );

    function fundingGoal(address tokenAddress) external view  returns (uint256);

    function getCurrentPrice(address tokenAddress) external view  returns (uint256 );

    function getProgress(address tokenAddress)  external view  returns (uint256 current, uint256 target) ;

    function getState(address tokenAddress) external view  returns (uint8);

    function getCollateral(address tokenAddress) external view  returns (uint256);

    function getTotalTokensAvailable(address tokenAddress) external view  returns (uint256);

    function getFeePercent(address tokenAddress) external view  returns (uint24 denominator ,uint256 percent);

    function getParam(address tokenAddress) external view  returns (BondingCurveParam memory param);

}
