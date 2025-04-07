// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IBondingCurve.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";


import "./BondingCurveUtil.sol";
import "./Token.sol";

contract BondingCurveHelper is Ownable{

    using FixedPointMathLib for uint256;

    // The main BondingCurve contract
    IBondingCurve public bondingCurve;
    BondingCurveUtil public bondingCurveUtil;
    IUniswapV3Factory public uniswapV3Factory;

    constructor() {
    }

    function setAddresses( address _bondingCurve,address _bondingCurveUtil,address _uniswapV3Factory ) external onlyOwner {
        bondingCurve = IBondingCurve(_bondingCurve);
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);
        uniswapV3Factory =  IUniswapV3Factory(_uniswapV3Factory);
    }

    // Struct to store the status information for a token
    struct TokenStatus {
        uint8 state;  // Current state of the token (as an uint8)
        uint256 fundingProgress;  // Progress of the funding phase (as a percentage)
        uint256 fundingGoal;  // Total funding goal (BaseToken)
        uint256 fundsCollateral;  // Total BaseToken

        uint256 publicFunding;  // public funding
        uint256 publicCollateral;  // public Collateral
        uint256 publicFundingProgress;  // public Collateral
        uint256 beeListFunding;  // bee list funding
        uint256 beeListCollateral;  // bee list Collateral
        uint256 beeFundingProgress;
        uint256 remainingTokens;  // Remaining tokens available for sale
        uint256 currentPrice;  // Current price of the token in BaseToken
        uint256 initPrice;  // init price of the token in BaseToken
        uint256 endTime;  // init price of the token in BaseToken
    }

    // Function to get the status for multiple tokens at once
    function getMultipleTokenStatus(address[] calldata tokenAddresses) external view returns (TokenStatus[] memory statuses) {
        uint256 length = tokenAddresses.length;
        statuses = new TokenStatus[](length);
        TokenStatus memory defaultStatus = TokenStatus({
            state: 0,               // State 0 can represent an error or invalid state
            fundingProgress: 0,     // No funding progress
            fundingGoal: 0,        // No goal achieved
            fundsCollateral: 0,    // No collateral
            publicFunding : 0,     //
            publicCollateral: 0,  //
            publicFundingProgress : 0,//
            beeListFunding : 0,   //
            beeListCollateral : 0, //
            beeFundingProgress: 0,//
            remainingTokens: 0,    // No tokens remaining
            currentPrice: 0,       // No current price
            initPrice: 0,         // No initial price
            endTime:0
        });
        // Iterate through each token address and populate the status
        for (uint256 i = 0; i < length; i++) {
            if(bondingCurve.getState(tokenAddresses[i]) == 0){
                statuses[i] = defaultStatus;  // If error, assign default error status
            }else{
                statuses[i] = _getTokenStatus(tokenAddresses[i]);
            }

        }
    }

    function getMaxBaseToken(address tokenAddress,address user, uint256 fundingBaseTokenAmount) external view returns (uint256 maxBaseToken) {
        uint remainingBaseToken = fundingBaseTokenAmount ;
        if(address(0) != tokenAddress){
            remainingBaseToken = bondingCurve.calculateRemainingBaseNeeded(tokenAddress,user);
        }
        (uint24 denominator ,uint256 percent ) = bondingCurve.getFeePercent();
        return remainingBaseToken * denominator/ (denominator - percent);
    }

    function getBuyPrice(address tokenAddress,uint256 amount ) external view returns (uint256 _current,uint256 _after) {
        // Get the current price of the token (BaseToken)
        _current = bondingCurve.getCurrentPrice(tokenAddress);
        _after = _current;
    }

    function getSellPrice(address tokenAddress,uint256 amount ) external view returns (uint256 _current,uint256 _after) {
        // Get the current price of the token (BaseToken)
        _current = bondingCurve.getCurrentPrice(tokenAddress);
        _after = _current;
    }

    // Function to get the status of a single token
    function getTokenStatus(address tokenAddress) external view returns (TokenStatus memory status) {
        return _getTokenStatus(tokenAddress);
    }

    // Internal function to get the status of a single token
    function _getTokenStatus(address tokenAddress) internal view returns (TokenStatus memory status) {
        // Get the current state of the token
        uint8 state = bondingCurve.getState(tokenAddress);

        // Get the progress
        (bool whiteListModel,uint256 current, uint256 target,uint256 beeCollateral,uint256 beeFunding) = bondingCurve.getProgress(tokenAddress);

        // Get the remaining tokens available for sale
        uint256 remainingTokens = bondingCurve.getTotalTokensAvailable(tokenAddress);

        //get init price
        uint256 initPrice = bondingCurve.getCurrentPrice(tokenAddress);

        // Calculate funding progress as a percentage
        uint256 fundingProgress = current* 1e18 / target;
        uint256 publicFunding = target - beeFunding;
        uint256 publicCollateral = current - beeCollateral;
        uint256 beeFundingProgress = beeFunding == 0 ? 0 :beeCollateral* 1e18 / beeFunding;
        uint256 publicFundingProgress = publicFunding == 0 ? 0 : publicCollateral* 1e18 / publicFunding;

        uint256 endTime = bondingCurve.getEnTime(tokenAddress);

        // Return the token status
        status = TokenStatus({
            state: state,
            fundingProgress: fundingProgress,
            fundingGoal: target,
            fundsCollateral: current,
            publicFunding : publicFunding,
            publicCollateral: publicCollateral,
            publicFundingProgress: publicFundingProgress,
            beeListFunding : beeFunding,
            beeListCollateral : beeCollateral ,
            beeFundingProgress:beeFundingProgress,
            remainingTokens: remainingTokens,
            currentPrice: initPrice,
            initPrice: initPrice,
            endTime: endTime
        });
    }

    function _calculateFee(uint256 _amount, uint24 _denominator,uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / _denominator;
    }

    function getPriceFromUniswap(address tokenIn,address tokenOut,uint24 fee) external view returns (uint256 price)
    {
        return _getPriceFromUniswap(tokenIn,tokenOut,fee);
    }
    function getPricesFromUniswap(address[] calldata tokenIns, address[] calldata tokenOuts, uint24 fee) external view returns (uint256[] memory prices) {
        require(tokenIns.length == tokenOuts.length, "Mismatched token arrays length");

        // 分配返回的价格数组
        prices = new uint256[](tokenIns.length);

        for (uint256 i = 0; i < tokenIns.length; i++) {
            prices[i] = _getPriceFromUniswap(tokenIns[i], tokenOuts[i], fee);
        }

        return prices;
    }

    function _getPriceFromUniswap(address tokenIn,address tokenOut,uint24 fee) internal view returns (uint256 price)
    {
        address poolAddress;

        try uniswapV3Factory.getPool(tokenIn, tokenOut, fee) returns (address pool) {
            poolAddress = pool;
        } catch {
            return 0;
        }

        if (poolAddress == address(0)) {
            return 0;
        }

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(poolAddress);

        try uniswapPool.slot0() returns (  uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked ) {
            return bondingCurveUtil.price(sqrtPriceX96);
        } catch {
            return 0;
        }
    }
}
