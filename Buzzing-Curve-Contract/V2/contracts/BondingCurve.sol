// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";


import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {BondingCurveUtil} from "./BondingCurveUtil.sol";
import {Token} from "./Token.sol";
import {ILocker} from "./interfaces/ILocker.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";
import {Referral} from "./Referral.sol";

contract BondingCurve is IBondingCurve, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    //The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    //The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;
    uint24 public constant FEE_DENOMINATOR = 10000; // Denominator for calculating fees
    uint24 public constant uniV3fee = 10000; //1%

    //version param
    int8 public activeVersion;
    mapping(address => int8) public tokenVersion;
    mapping(int8 => BondingCurveParam) public versionParams;

    mapping(address => TokenState) public tokens; // Tracks the current state of each token
    mapping(address => uint256) public collateral; // Collateral (baseToken) per token
    address public tokenImplementation; // Implementation address for cloning tokens

    uint256 public totalFee; // Accumulated protocol fees
    uint256 public totalCreationFee;
    uint256 public totalLiquidityFee;
    uint256 public totalCreatorReward;


    mapping(address => address) public tokenCreators;


    // Mapping to store accumulated referral rewards for each referrer
    mapping(address => uint256) public referralRewards; // referrer => total reward


    address payable public  treasury; // Treasury address to store collected fees
    address public lockLPAddress ;
    IERC20 public baseToken;
    INonfungiblePositionManager public positionManager; // Uniswap V3 Position Manager address
    IUniswapV3Factory public uniswapV3Factory; // Uniswap V3 Factory address
    Referral public referralCa;
    BondingCurveUtil public bondingCurveUtil;


    constructor() {

    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    // Token functions
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialBuyAmount,
        string memory businessKey,
        uint256 daoId,
        address referralAddress
    ) external payable nonReentrant returns (address) {
        address tokenAddress = Clones.clone(tokenImplementation);
        Token token = Token(tokenAddress);
        token.initialize(name, symbol,businessKey,daoId);
        tokens[tokenAddress] = TokenState.FUNDING;
        tokenCreators[tokenAddress] = msg.sender;
        tokenCreators[tokenAddress] = msg.sender;
        tokenVersion[tokenAddress] = activeVersion;

        BondingCurveParam memory bondingCurveParam = versionParams[activeVersion];
        baseToken.transferFrom(msg.sender,address(this), bondingCurveParam.creationFee + initialBuyAmount);
        if (bondingCurveParam.creationFee > 0) {
            require(baseToken.transfer(treasury, bondingCurveParam.creationFee), "Creation fee transfer to treasury failed");
            totalCreationFee += bondingCurveParam.creationFee;
        }
        if (initialBuyAmount > 0) {
            _buy(tokenAddress, 0,initialBuyAmount,referralAddress);
        }else{
            referralCa.setReferral(msg.sender,referralAddress);
        }
        CreatePoolParam memory param = _creatPoolParams(tokenAddress);
        address pool = _createLiquidityPool(param.token0,param.token1,param.fee,param.sqrtPriceX96);
        token.setPool(pool);
        emit TokenCreated(msg.sender,tokenAddress,symbol,name, bondingCurveParam.creationFee,initialBuyAmount,block.timestamp, businessKey, daoId);
        return tokenAddress;
    }

    function buy(address tokenAddress, uint256 minAmountOut,uint256 baseAmount,address referralAddress) external payable nonReentrant {
        baseToken.transferFrom(msg.sender,address(this), baseAmount);
        _buy(tokenAddress,minAmountOut,baseAmount,referralAddress);
    }

    function _buy(address tokenAddress, uint256 minAmountOut,uint256 buyAmount,address referralAddress) internal   {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];

        uint256 tokenCollateral = collateral[tokenAddress];
        uint256 remainingTokenNeeded = bondingCurveParam.fundingGoal - tokenCollateral;

        uint256 _fee = _calculateFee(buyAmount, bondingCurveParam.feePercent);
        uint256 contributionWithoutFee = buyAmount - _fee;
        uint256 adjustedMinAmountOut = minAmountOut;
        if (contributionWithoutFee > remainingTokenNeeded) {
            contributionWithoutFee = remainingTokenNeeded;
            adjustedMinAmountOut = (minAmountOut * contributionWithoutFee) / buyAmount;
            _fee =(contributionWithoutFee * bondingCurveParam.feePercent) / (FEE_DENOMINATOR - bondingCurveParam.feePercent);
        }
        totalFee += _fee;
        uint256 actualContribution = contributionWithoutFee + _fee;
        uint256 refundAmount = buyAmount > actualContribution ? buyAmount - actualContribution : 0;

        // Calculate the amount of tokens to transfer using the Bonding Curve
        Token token = Token(tokenAddress);
        uint256 amountOut = bondingCurveUtil.getAmountOut(tokenCollateral, contributionWithoutFee,
            bondingCurveParam.A,bondingCurveParam.B,bondingCurveParam.C );

        uint256 availableSupply =  token.balanceOf(address (this)) - bondingCurveParam.initialSupply ;
        require(amountOut <= availableSupply, "Token supply not enough");
        require(amountOut >= adjustedMinAmountOut, "Slippage: insufficient output amount");

        tokenCollateral += contributionWithoutFee;

        token.transfer(msg.sender, amountOut);

        if (tokenCollateral >= bondingCurveParam.fundingGoal) {
            AddLiquidityParam memory initParam =_addLiquidityParams(tokenAddress,bondingCurveParam.initialSupply + availableSupply - amountOut , tokenCollateral);
            address pool = _createLiquidityPool(initParam.token0,initParam.token1,initParam.fee,initParam.sqrtPriceX96);
            //enable sending
            token.enableSendingToPool();
            uint256 tokenId = _addLiquidity(initParam);
            _transferFee(tokenAddress);
            _burnLiquidityToken( tokenId,tokenAddress);
            tokens[tokenAddress] = TokenState.TRADING;
        }
        collateral[tokenAddress] = tokenCollateral;

        referralCa.setReferral(msg.sender,referralAddress);
        address referrer = referralCa.getReferrer(msg.sender); // Get the referrer address

        if (referrer != address(0)) {
            // Referral reward logic
            uint256 referralReward = (_fee * bondingCurveParam.referralFeePercent) / FEE_DENOMINATOR; // Calculate the referral reward
            _fee -= referralReward;
            // Transfer the referral reward to the referrer
            require(baseToken.transfer(referrer, referralReward), "Referral reward transfer failed");
            emit ReferralRewardPaid(msg.sender,referrer, referralReward, block.timestamp);
        }

        if (_fee  > 0) {
            require(baseToken.transfer(treasury, _fee), "Fee transfer to treasury failed");
            emit FeeTransferred(msg.sender, treasury, _fee, block.timestamp);
        }
        if (refundAmount > 0) {
            require(baseToken.transfer(msg.sender, refundAmount), "Refund failed");
        }
        emit TokenBought(msg.sender, tokenAddress, actualContribution, amountOut, _fee, block.timestamp);
    }

    function sell(address tokenAddress,address referralAddress, uint256 amount, uint256 minAmountOut) external nonReentrant {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(tokenAddress).transferFrom(msg.sender,address(this), amount), "transfer error");

        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];
        Token token = Token(tokenAddress);
        uint256 receivedBaseToken = bondingCurveUtil.getFundsReceived(collateral[tokenAddress], amount,
            bondingCurveParam.A,bondingCurveParam.B,bondingCurveParam.C);
        require(receivedBaseToken >= minAmountOut, "Slippage: insufficient output amount");
        collateral[tokenAddress] -= receivedBaseToken;
        uint256 _fee = _calculateFee(receivedBaseToken, bondingCurveParam.feePercent);
        totalFee += _fee;
        receivedBaseToken -= _fee;
        require(receivedBaseToken > 0, "Insufficient baseAmount received after fee deduction");

        require(baseToken.transfer(msg.sender, receivedBaseToken), "base token send failed");

        referralCa.setReferral(msg.sender,referralAddress);

        address referrer = referralCa.getReferrer(msg.sender); // Get the referrer address

        if (referrer != address(0)) {
            // Referral reward logic
            uint256 referralReward = (_fee * bondingCurveParam.referralFeePercent) / FEE_DENOMINATOR; // Calculate the referral reward
            _fee -= referralReward;
            // Transfer the referral reward to the referrer
            require(baseToken.transfer(referrer, referralReward), "Referral reward transfer failed");
            emit ReferralRewardPaid(msg.sender,referrer, referralReward, block.timestamp);
        }

        if (_fee  > 0) {
            require(baseToken.transfer(treasury, _fee), "Fee transfer to treasury failed");
            emit FeeTransferred(msg.sender, treasury, _fee, block.timestamp);
        }
        emit TokenSold(msg.sender, tokenAddress, amount, receivedBaseToken,_fee, block.timestamp);
    }

    function _createLiquidityPool( address token0,address token1,uint24 _uniV3fee,uint160 sqrtPriceX96) internal returns (address) {
       address pool =  positionManager.createAndInitializePoolIfNecessary(token0,token1
           ,_uniV3fee,sqrtPriceX96);
        require(pool != address(0),"create pool error " );
        return pool;
    }

    function _addLiquidityParams(address tokenAddress, uint256 tokenAmount, uint256 baseTokenAmount ) internal view returns (AddLiquidityParam memory addLiquidityParam) {
        // Ensure sufficient base token is provided after fees and creator reward
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];
        require(baseTokenAmount > bondingCurveParam.liquidityFee + bondingCurveParam.creatorReward, "addLiquidity INSUFFICIENT_TOKEN");

        uint256 addLqBaseTokenAmount = baseTokenAmount - bondingCurveParam.liquidityFee - bondingCurveParam.creatorReward;

        // Assign token0 and token1 based on the comparison of tokenAddress and baseToken
        addLiquidityParam.token0 = tokenAddress < address(baseToken) ? tokenAddress : address(baseToken);
        addLiquidityParam.token1 = tokenAddress < address(baseToken) ? address(baseToken) : tokenAddress;

        // Assign amounts for token0 and token1
        addLiquidityParam.amount0 = tokenAddress < address(baseToken) ? tokenAmount : addLqBaseTokenAmount;
        addLiquidityParam.amount1 = tokenAddress < address(baseToken) ? addLqBaseTokenAmount : tokenAmount;
        addLiquidityParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        addLiquidityParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,bondingCurveParam.initialSupply,bondingCurveParam.fundingGoal);

        // Return the constructed InitParam struct
        return addLiquidityParam;
    }
    function _creatPoolParams(address tokenAddress ) internal view returns (CreatePoolParam memory createPoolParam) {
        // Assign token0 and token1 based on the comparison of tokenAddress and baseToken
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];

        createPoolParam.token0 = tokenAddress < address(baseToken) ? tokenAddress : address(baseToken);
        createPoolParam.token1 = tokenAddress < address(baseToken) ? address(baseToken) : tokenAddress;

        createPoolParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        createPoolParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,bondingCurveParam.initialSupply,bondingCurveParam.fundingGoal);
        // Return the constructed InitParam struct
        return createPoolParam;
    }

    function _initSqrtPriceX96(address _tokenAddress,uint256 _tokenAmount,uint256 _baseTokenAmount) internal view returns(uint160)  {
        (uint256 amount0,uint256 amount1) =  _tokenAddress < address(baseToken) ? ( _tokenAmount,_baseTokenAmount) : (_baseTokenAmount,_tokenAmount);
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[_tokenAddress]];

     return bondingCurveUtil.calculateSqrtPriceX96(amount0,amount1);
    }

    function _addLiquidity(AddLiquidityParam memory initParam) internal returns (uint256) {

        int24 tickSpacing = IUniswapV3Factory(uniswapV3Factory).feeAmountTickSpacing(initParam.fee);
        require(tickSpacing != 0 , "Invalid tick");
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: initParam.token0,
            token1: initParam.token1,
            fee: initParam.fee, // 1%
            tickLower: minUsableTick(tickSpacing),
            tickUpper: maxUsableTick(tickSpacing),
            amount0Desired: initParam.amount0,
            amount1Desired: initParam.amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 30
        });


        IERC20(initParam.token0).approve(address(positionManager), initParam.amount0);
        IERC20(initParam.token1).approve(address(positionManager), initParam.amount1);

        (uint256 tokenId, uint128 liquidity,uint256 amount0,uint256 amount1  ) = positionManager.mint(params);
        // Emit event to log the liquidity addition
        emit TokenLiquidityAdded(
            initParam.token0,       // Address of token0
            amount0,      // Amount of token0 added to the liquidity pool
            amount1,      // Amount of token1 added to the liquidity pool
            initParam.sqrtPriceX96, // Initial price (square root of price)
            initParam.fee,          // Fee tier for the liquidity pool
            block.timestamp        // Current timestamp
        );
        return tokenId;
    }

    function _transferFee(
        address tokenAddress
    ) internal  {
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];

        if (bondingCurveParam.liquidityFee > 0) {
            require(baseToken.transfer(treasury, bondingCurveParam.liquidityFee), "Liquidity fee transfer to treasury failed");
            totalLiquidityFee += bondingCurveParam.liquidityFee;
        }

        if (bondingCurveParam.creatorReward > 0) {
            require(baseToken.transfer(tokenCreators[tokenAddress], bondingCurveParam.creatorReward), "Creator reward transfer failed");
            totalCreatorReward += bondingCurveParam.creatorReward;
        }
    }

    function _burnLiquidityToken(uint256 tokenId,address tokenAddress) internal {
        // Transfer the LP token (Uniswap V3 liquidity token) to the lock address
        positionManager.safeTransferFrom(address(this), lockLPAddress, tokenId);

        // Trigger the initializer function in the lock contract to lock the LP token
        ILocker(lockLPAddress).add(tokenAddress,tokenId,tokenCreators[tokenAddress]);
    }

    function getAmountOut(address tokenAddress, uint256 baseAmount) external view returns (uint256 tokenAmount) {
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
        uint256 currentBaseAmount = collateral[tokenAddress];
        tokenAmount = bondingCurveUtil.getAmountOut(currentBaseAmount, baseAmount - _calculateFee(baseAmount, bondingCurveParam.feePercent)
        ,bondingCurveParam.A,bondingCurveParam.B,bondingCurveParam.C);
    }

    function getFundsReceived(address tokenAddress, uint256 deltaToken) external view returns (uint256 received) {
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
        uint256 currentBaseAmount = collateral[tokenAddress];
        received = bondingCurveUtil.getFundsReceived(currentBaseAmount, deltaToken,
            bondingCurveParam.A,bondingCurveParam.B,bondingCurveParam.C);
        received -= _calculateFee(received, bondingCurveParam.feePercent);
    }

    function _calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / FEE_DENOMINATOR;
    }

    function maxUsableTick(int24 tickSpacing) public pure returns (int24) {
        unchecked {
            return (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }
    function minUsableTick(int24 tickSpacing) public pure returns (int24) {
        unchecked {
            return (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    function setAddresses(
        address _tokenImplementation,
        address _baseToken,
        address _uniswapV3Factory,
        address _positionManager,
        address payable _treasury,
        address _lockLPAddress,
        address _referralCa,
        address _bondingCurveUtil

    ) external onlyOwner {
        tokenImplementation = _tokenImplementation;
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        positionManager = INonfungiblePositionManager(_positionManager);
        baseToken = IERC20(_baseToken);
        treasury = _treasury;
        lockLPAddress = _lockLPAddress;
        referralCa = Referral(_referralCa);
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);

    }

    function setLockAddress(address _lockLPAddress) external onlyOwner {
        lockLPAddress = _lockLPAddress;
    }

    function setUniswapAddress(address _uniswapV3Factory,address _positionManager) external onlyOwner {
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function setTreasury(address payable _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryUpdated(treasury);
    }

    function withdrawWETH(uint256 amount,address receipt) external onlyOwner {
        require(amount <= IERC20(baseToken).balanceOf(address(this)), "Insufficient baseToken balance");
        IERC20(baseToken).transfer(receipt, amount);
    }

    function fundingGoal(address tokenAddress) external view override returns (uint256){
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
        return bondingCurveParam.fundingGoal;
    }
    function getCurrentPrice(address tokenAddress) external view override returns (uint256 ) {
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
        uint256 currentBaseAmount = collateral[tokenAddress];
        return bondingCurveUtil.getCurrentPrice(currentBaseAmount,bondingCurveParam.A,bondingCurveParam.B,bondingCurveParam.C);
    }
    function getProgress(address tokenAddress)  external view  override returns (uint256 raised, uint256 target)  {
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
         if(tokens[tokenAddress] == TokenState.TRADING){
                return (bondingCurveParam.fundingGoal,bondingCurveParam.fundingGoal);
            }
            return ( collateral[tokenAddress],bondingCurveParam.fundingGoal);
        }
    function getState(address tokenAddress) external view override returns (uint8){
        return uint8(tokens[tokenAddress]);
    }

    function getCollateral(address tokenAddress) external view override returns (uint256){
        return collateral[tokenAddress];
    }

    function getTotalTokensAvailable(address tokenAddress) external view override returns (uint256){
        if(tokens[tokenAddress] == TokenState.TRADING){
            return 0;
        }
        BondingCurveParam memory bondingCurveParam = versionParams[tokenVersion[tokenAddress]];
        return IERC20(tokenAddress).balanceOf(address(this)) - bondingCurveParam.initialSupply;
    }

    function getFeePercent(address tokenAddress) external view override returns (uint24,uint256){
        BondingCurveParam memory bondingCurveParam = tokenAddress == address(0) ? versionParams[activeVersion] : versionParams[tokenVersion[tokenAddress]];
        return (FEE_DENOMINATOR, bondingCurveParam.feePercent);
    }

    function getParam(address tokenAddress) external view  returns (BondingCurveParam memory param){
        if( tokenAddress == address(0)){
            return versionParams[activeVersion];
        }
        return versionParams[tokenVersion[tokenAddress]];
    }

    function setParam(int8 version,BondingCurveParam memory param,bool active) external onlyOwner {
        if(active){
            activeVersion = version;
        }
         versionParams[version] = param;
    }

    function authorizeUpgrade(address newImplementation) public {
        _authorizeUpgrade(newImplementation);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
