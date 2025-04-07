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
import {IWETH} from "./interfaces/IWETH.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";

contract BondingCurve is IBondingCurve, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

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

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint256 public constant MAX_SUPPLY = 10 ** 9 * 1e18; // Maximum token supply
    uint256 public constant FUNDING_SUPPLY = 733058550 * 1e18; // 73.3% for funding
    uint256 public constant INITIAL_SUPPLY = MAX_SUPPLY - FUNDING_SUPPLY; // 26.7% for initial liquidity
    uint256 public constant FUNDING_GOAL = 2048733358 * 1e9; // Target ETH for funding phase
    uint24 public constant FEE_DENOMINATOR = 10000; // Denominator for calculating fees

    mapping(address => TokenState) public tokens; // Tracks the current state of each token
    mapping(address => uint256) public collateral; // Collateral (ETH) per token
    address public  tokenImplementation; // Implementation address for cloning tokens

    address public uniswapV3Factory; // Uniswap V3 Factory address
    INonfungiblePositionManager public positionManager; // Uniswap V3 Position Manager address
    address public WETH;  // WETH address
    uint24 public constant uniV3fee = 10000; //1%
    address public lockLPAddress ; //1%


    BondingCurveUtil public bondingCurveUtil; // Instance of the BondingCurveUtil.sol.sol contract
    uint256 public feePercent; // Fee percentage (basis points)
    uint256 public fee; // Accumulated protocol fees
    uint256 public totalCreationFee;
    uint256 public totalLiquidityFee;
    uint256 public totalCreatorReward;


    address payable public  treasury; // Treasury address to store collected fees
    uint256 public creationFee ;
    uint256 public liquidityFee ;
    uint256 public creatorReward ;
    mapping(address => address) public tokenCreators;

    // Mapping to store the referrer of each user
    mapping(address => address) public referrals; // user => referrer

    // Mapping to store accumulated referral rewards for each referrer
    mapping(address => uint256) public referralRewards; // referrer => total reward

    uint256 public referralFeePercent ;//Referral fee percentage



    // Events
    event TokenCreated (address indexed user,address indexed token,string symbol,string name,uint256 creationFee,uint256 initialBuyAmount,uint256 timestamp, string businessKey, uint256 daoId);
    event TokenBought(address indexed buyer, address indexed tokenAddress, uint256 amountIn, uint256 amountOut, uint256 fee,uint256 timestamp);
    event TokenSold(address indexed seller, address indexed tokenAddress, uint256 amountIn, uint256 amountOut,uint256 fee,uint256 timestamp);
    event TreasuryUpdated(address newTreasury);
    event FeesUpdated(uint256 newCreationFee, uint256 newLiquidityFee, uint256 newCreatorReward);
    event CreationFeeUpdated(uint256 newCreationFee);
    event LiquidityFeeUpdated(uint256 newLiquidityFee);
    event CreatorRewardUpdated(uint256 newCreatorReward);
    event FeeTransferred(address indexed payer, address indexed treasury, uint256 feeAmount, uint256 timestamp);
    event ReferralUpdated(address indexed user, address indexed referrer);
    event ReferralRewardPaid(address indexed user,address indexed referrer, uint256 rewardAmount, uint256 timestamp);
    event ReferralFeePercentUpdated(uint256 newReferralFeePercent);

    event TokenLiquidityAdded(
        address indexed token,  // Token address of the liquidity pool
        uint256 amount0,        // Amount of token0 added to the liquidity pool
        uint256 amount1,        // Amount of token1 added to the liquidity pool
        uint160 sqrtPriceX96,   // Initial price of the pool (square root of price)
        uint24 fee,             // Fee percentage for the liquidity pool
        uint256 timestamp       // Timestamp when the liquidity was added
    );

    constructor() {
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        creationFee = 2e15;//0.002
        liquidityFee = 1e17;//0.1
        creatorReward = 1e16;//0.01
        referralFeePercent = 5000; // 50%

    }

    function setAddresses(
        address _tokenImplementation,
        address _WETH,
        address _uniswapV3Factory,
        address _positionManager,
        address _bondingCurveUtil,
        uint256 _feePercent,
        address payable _treasury,
        address _lockLPAddress
    ) external onlyOwner {
        tokenImplementation = _tokenImplementation;
        uniswapV3Factory = _uniswapV3Factory;
        positionManager = INonfungiblePositionManager(_positionManager);
        WETH = _WETH;
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);
        feePercent = _feePercent;
        treasury = _treasury;
        lockLPAddress = _lockLPAddress;

    }

    // Admin functions
    function setBondingCurveUtil(address _bondingCurveUtil) external onlyOwner {
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);
    }
    function setLockAddress(address _lockLPAddress) external onlyOwner {
        lockLPAddress = _lockLPAddress;
    }

    function setUniswapAddress(address _uniswapV3Factory,address _positionManager) external onlyOwner {
        uniswapV3Factory = _uniswapV3Factory;
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function setTreasury(address payable _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryUpdated(treasury);
    }
    function setFees(uint256 _creationFee, uint256 _liquidityFee, uint256 _creatorReward) external onlyOwner {
        creationFee = _creationFee;
        liquidityFee = _liquidityFee;
        creatorReward = _creatorReward;
        emit FeesUpdated(creationFee, liquidityFee, creatorReward);
    }
    function setCreationFee(uint256 _creationFee) external onlyOwner {
        creationFee = _creationFee;
        emit CreationFeeUpdated(creationFee);
    }

    function setLiquidityFee(uint256 _liquidityFee) external onlyOwner {
        liquidityFee = _liquidityFee;
        emit LiquidityFeeUpdated(liquidityFee);
    }

    function setCreatorReward(uint256 _creatorReward) external onlyOwner {
        creatorReward = _creatorReward;
        emit CreatorRewardUpdated(creatorReward);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        feePercent = _feePercent;
    }

    // Function to update the referral fee percentage
    function setReferralFeePercent(uint256 _newReferralFeePercent) external onlyOwner {
        require(_newReferralFeePercent <= 10000, "Referral fee can't exceed 100%");
        referralFeePercent = _newReferralFeePercent;
        emit ReferralFeePercentUpdated(referralFeePercent);
    }

    function _setReferral(address referrer) internal {
        require(referrer != msg.sender, "You cannot refer yourself");
        if(referrals[msg.sender] != address(0)){
           return;
        }
        referrals[msg.sender] = referrer;
        emit ReferralUpdated(msg.sender, referrer);
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

        require(msg.value >= creationFee + initialBuyAmount, "Insufficient ETH sent for token creation");
        uint256 refundEth = msg.value- creationFee - initialBuyAmount;
        if (creationFee > 0) {
            (bool sentCreationFee, ) = treasury.call{value: creationFee}("");
            require(sentCreationFee, "Creation fee transfer to treasury failed");
            totalCreationFee += creationFee;
        }
        if(refundEth > 0 ){
            (bool refundEthFee, ) = msg.sender.call{value: refundEth}("");
            require(refundEthFee, "refund eth failed");
        }

        if (initialBuyAmount > 0) {
            _buy(tokenAddress, 0,initialBuyAmount,referralAddress,initialBuyAmount);
        }else{
            _setReferral(referralAddress);
        }
        CreatePoolParam memory param = _creatPoolParams(tokenAddress);
        address pool = _createLiquidityPool(param.token0,param.token1,param.fee,param.sqrtPriceX96);
        token.setPool(pool);
        emit TokenCreated(msg.sender,tokenAddress,symbol,name, creationFee,initialBuyAmount,block.timestamp, businessKey, daoId);
        return tokenAddress;
    }
    function buy(address tokenAddress, uint256 minAmountOut,uint256 ethAmount,address referralAddress) external payable nonReentrant {
        _buy(tokenAddress,minAmountOut,ethAmount,referralAddress,msg.value);
    }

    function _buy(address tokenAddress, uint256 minAmountOut,uint256 buyAmount,address referralAddress,uint256 receiveEth) internal   {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        require(msg.value >= buyAmount, "ETH not enough");
        uint256 valueToBuy = buyAmount;
        uint256 tokenCollateral = collateral[tokenAddress];
        uint256 remainingEthNeeded = FUNDING_GOAL - tokenCollateral;

        uint256 _fee = _calculateFee(valueToBuy, feePercent);
        uint256 contributionWithoutFee = valueToBuy - _fee;
        uint256 adjustedMinAmountOut = minAmountOut;
        if (contributionWithoutFee > remainingEthNeeded) {
            contributionWithoutFee = remainingEthNeeded;
            adjustedMinAmountOut = (minAmountOut * contributionWithoutFee) / valueToBuy;
            _fee =(contributionWithoutFee * feePercent) / (FEE_DENOMINATOR - feePercent);
        }
        fee += _fee;
        uint256 actualContribution = contributionWithoutFee + _fee;
        uint256 refundAmount = receiveEth > actualContribution ? receiveEth - actualContribution : 0;

        // Calculate the amount of tokens to transfer using the Bonding Curve
        Token token = Token(tokenAddress);
        uint256 amountOut = bondingCurveUtil.getAmountOut(tokenCollateral, contributionWithoutFee );

        uint256 availableSupply =  token.balanceOf(address (this)) - INITIAL_SUPPLY ;
        require(amountOut <= availableSupply, "Token supply not enough");
        require(amountOut >= adjustedMinAmountOut, "Slippage: insufficient output amount");

        tokenCollateral += contributionWithoutFee;

        token.transfer(msg.sender, amountOut);

        if (tokenCollateral >= FUNDING_GOAL) {
            AddLiquidityParam memory initParam =_addLiquidityParams(tokenAddress,INITIAL_SUPPLY + availableSupply - amountOut , tokenCollateral);
            address pool = _createLiquidityPool(initParam.token0,initParam.token1,initParam.fee,initParam.sqrtPriceX96);
            //enable sending
            token.enableSendingToPool();
            uint256 tokenId = _addLiquidity(initParam);
            _transferFee(tokenAddress);
            _burnLiquidityToken( tokenId,tokenAddress);
            tokens[tokenAddress] = TokenState.TRADING;
        }
        collateral[tokenAddress] = tokenCollateral;

        _setReferral(referralAddress);
        address referrer = referrals[msg.sender]; // Get the referrer address

        if (referrer != address(0)) {
            // Referral reward logic
            uint256 referralReward = (_fee * referralFeePercent) / FEE_DENOMINATOR; // Calculate the referral reward
            _fee -= referralReward;
            // Transfer the referral reward to the referrer
            (bool sentReferralReward, ) = payable(referrer).call{value: referralReward}("");
            require(sentReferralReward, "Referral reward transfer failed");
            emit ReferralRewardPaid(msg.sender,referrer, referralReward, block.timestamp);
        }

        if (_fee  > 0) {
            (bool sent, ) = treasury.call{value: _fee}("");
            require(sent, "Fee transfer to treasury failed");
            emit FeeTransferred(msg.sender, treasury, _fee, block.timestamp);
        }
        if (refundAmount > 0) {
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Refund failed");
        }
        emit TokenBought(msg.sender, tokenAddress, actualContribution, amountOut, _fee, block.timestamp);
    }

    function sell(address tokenAddress,address referralAddress, uint256 amount, uint256 minAmountOut) external nonReentrant {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        require(amount > 0, "Amount must be greater than zero");

        Token token = Token(tokenAddress);
        uint256 receivedETH = bondingCurveUtil.getFundsReceived(collateral[tokenAddress], amount);
        require(receivedETH >= minAmountOut, "Slippage: insufficient output amount");
        collateral[tokenAddress] -= receivedETH;
        uint256 _fee = _calculateFee(receivedETH, feePercent);
        fee += _fee;
        receivedETH -= _fee;
        require(receivedETH > 0, "Insufficient ETH received after fee deduction");

        token.transferFrom(msg.sender,address(this), amount);
        (bool success, ) = msg.sender.call{value: receivedETH}(new bytes(0));
        require(success, "ETH send failed");

        _setReferral(referralAddress);


        address referrer = referrals[msg.sender]; // Get the referrer address

        if (referrer != address(0)) {
            // Referral reward logic
            uint256 referralReward = (_fee * referralFeePercent) / FEE_DENOMINATOR; // Calculate the referral reward
            _fee -= referralReward;
            // Transfer the referral reward to the referrer
            (bool sentReferralReward, ) = payable(referrer).call{value: referralReward}("");
            require(sentReferralReward, "Referral reward transfer failed");
            emit ReferralRewardPaid(msg.sender,referrer, referralReward, block.timestamp);
        }

        if (_fee  > 0) {
            (bool sent, ) = treasury.call{value: _fee }("");
            require(sent, "Fee transfer to treasury failed");
            emit FeeTransferred(msg.sender, treasury, _fee, block.timestamp);
        }
        emit TokenSold(msg.sender, tokenAddress, amount, receivedETH,_fee, block.timestamp);
    }

    function _createLiquidityPool( address token0,address token1,uint24 _uniV3fee,uint160 sqrtPriceX96) internal returns (address) {
       address pool =  positionManager.createAndInitializePoolIfNecessary(token0,token1
           ,_uniV3fee,sqrtPriceX96);
        require(pool != address(0),"create pool error " );
        return pool;
    }

    function _addLiquidityParams(address tokenAddress, uint256 tokenAmount, uint256 ethAmount ) internal returns (AddLiquidityParam memory addLiquidityParam) {
        // Ensure sufficient ETH is provided after fees and creator reward
        require(ethAmount > liquidityFee + creatorReward, "addLiquidity INSUFFICIENT_ETH");

        uint256 addLqEthAmount = ethAmount - liquidityFee - creatorReward;

        // Assign token0 and token1 based on the comparison of tokenAddress and WETH
        addLiquidityParam.token0 = tokenAddress < WETH ? tokenAddress : WETH;
        addLiquidityParam.token1 = tokenAddress < WETH ? WETH : tokenAddress;

        // Assign amounts for token0 and token1
        addLiquidityParam.amount0 = tokenAddress < WETH ? tokenAmount : addLqEthAmount;
        addLiquidityParam.amount1 = tokenAddress < WETH ? addLqEthAmount : tokenAmount;
        addLiquidityParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        addLiquidityParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress);

        // Return the constructed InitParam struct
        return addLiquidityParam;
    }
    function _creatPoolParams(address tokenAddress ) internal returns (CreatePoolParam memory createPoolParam) {
        // Assign token0 and token1 based on the comparison of tokenAddress and WETH
        createPoolParam.token0 = tokenAddress < WETH ? tokenAddress : WETH;
        createPoolParam.token1 = tokenAddress < WETH ? WETH : tokenAddress;

        createPoolParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        createPoolParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress);

        // Return the constructed InitParam struct
        return createPoolParam;
    }

    function _initSqrtPriceX96(address _tokenAddress) internal view returns(uint160)  {
        return _tokenAddress < WETH ? 6751903237628121114059408 : 929669463249474346166363809297474;
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

        if (initParam.token0 == WETH) {
            IWETH(WETH).deposit{value: initParam.amount0}();
        }else if (initParam.token1 == WETH) {
            IWETH(WETH).deposit{value: initParam.amount1}();
        }
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
        if (liquidityFee > 0) {
            (bool sentLiquidityFee, ) = treasury.call{value: liquidityFee}("");
            require(sentLiquidityFee, "Liquidity fee transfer to treasury failed");
            totalLiquidityFee += liquidityFee;
        }

        if (creatorReward > 0) {
            (bool sentCreatorReward, ) = payable(tokenCreators[tokenAddress]).call{value: creatorReward}("");
            require(sentCreatorReward, "Creator reward transfer failed");
            totalCreatorReward += creatorReward;
        }
    }

    function _burnLiquidityToken(uint256 tokenId,address tokenAddress) internal {
        // Transfer the LP token (Uniswap V3 liquidity token) to the lock address
        positionManager.safeTransferFrom(address(this), lockLPAddress, tokenId);

        // Trigger the initializer function in the lock contract to lock the LP token
        ILocker(lockLPAddress).add(tokenAddress,tokenId,tokenCreators[tokenAddress]);
    }

    function getAmountOut(address tokenAddress, uint256 ethAmount) external view returns (uint256 tokenAmount) {
        uint256 currentEth = collateral[tokenAddress];
        tokenAmount = bondingCurveUtil.getAmountOut(currentEth, ethAmount - _calculateFee(ethAmount, feePercent));
    }

    function getFundsReceived(address tokenAddress, uint256 deltaToken) external view returns (uint256 ethReceived) {
        uint256 currentEth = collateral[tokenAddress];
        ethReceived = bondingCurveUtil.getFundsReceived(currentEth, deltaToken);
        ethReceived -= _calculateFee(ethReceived, feePercent);
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

    function withdrawWETH(uint256 amount,address receipt) external onlyOwner {
        require(amount <= IERC20(WETH).balanceOf(address(this)), "Insufficient WETH balance");
        IERC20(WETH).transfer(receipt, amount);
    }

    function fundingGoal() external view override returns (uint256){
        return FUNDING_GOAL;
    }
    function getCurrentPrice(address tokenAddress) external view override returns (uint256 ) {
        uint256 currentEth = collateral[tokenAddress];
        return bondingCurveUtil.getCurrentPrice(currentEth);
    }
    function getProgress(address tokenAddress)  external view  override returns (uint256 raised, uint256 target)  {
        if(tokens[tokenAddress] == TokenState.TRADING){
            return (FUNDING_GOAL,FUNDING_GOAL);
        }
        return ( collateral[tokenAddress],FUNDING_GOAL);
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
       return IERC20(tokenAddress).balanceOf(address(this)) - INITIAL_SUPPLY;
    }

    function getFeePercent() external view override returns (uint24,uint256){
        return (FEE_DENOMINATOR, feePercent);
    }

    function authorizeUpgrade(address newImplementation) public {
        _authorizeUpgrade(newImplementation);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
