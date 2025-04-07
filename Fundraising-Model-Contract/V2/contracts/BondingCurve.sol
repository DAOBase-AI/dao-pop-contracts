// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter02} from "./interfaces/ISwapRouter02.sol";


import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BondingCurveUtil} from "./BondingCurveUtil.sol";
import {Token} from "./Token.sol";
import {Referral} from "./Referral.sol";

import {ILocker} from "./interfaces/ILocker.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";
import {Treasury} from "./Treasury.sol";


contract BondingCurve is IBondingCurve, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    enum TokenState {
        NOT_CREATED,
        FUNDING,
        TRADING,
        FAILED
    }
    struct AddLiquidityParam {
        address token0 ;
        address token1 ;
        uint256 amount0 ;
        uint256 amount1 ;
        int24 tickLower ;
        int24 tickUpper ;
        uint160 sqrtPriceX96 ;
        uint24 fee ;
    }

    struct CreatePoolParam {
        address token0 ;
        address token1 ;
        uint160 sqrtPriceX96 ;
        uint24 fee ;
    }

    uint256 public constant MAX_SUPPLY = 1100000000 * 1e18; // Maximum token supply
    uint256 public constant FUNDING_SUPPLY = 1000000000 * 1e18; // 80% for funding
    uint256 public constant INITIAL_SUPPLY = MAX_SUPPLY - FUNDING_SUPPLY; // 20% for initial liquidity
    uint24 public constant FEE_DENOMINATOR = 10000; // Denominator for calculating fees

    mapping(address => TokenState) public tokens; // Tracks the current state of each token
    address public  tokenImplementation; // Implementation address for cloning tokens
    address public  treasuryImplementation; // Implementation address for cloning treasury

    mapping(address => uint256) public collateral; // Collateral (baseToken)
    mapping(address => uint256) public whitelistCollateral; // whitelistCollateral (baseToken)

    mapping(address => uint256) public tokenFundingGoal; // Target baseToken for funding phase
    mapping(address => uint256) public whitelistFunding; // whitelist Target baseToken for funding phase
    mapping(address => uint256) public endTime; // phase end time
    mapping(address => bool) public whitelistModel; // phase end time


    address public uniswapV3Factory; // Uniswap V3 Factory address
    INonfungiblePositionManager public positionManager; // Uniswap V3 Position Manager address
    ISwapRouter02 public swapRouter02; // Uniswap V3 Position Manager address
    IERC20 public baseToken;  // baseToken address
    uint24 public constant uniV3fee = 10000; //1%
    address public lockLPAddress ; //1%


    BondingCurveUtil public bondingCurveUtil; // Instance of the BondingCurveUtil.sol contract
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


    // Mapping to store accumulated referral rewards for each referrer
    mapping(address => uint256) public referralRewards; // referrer => total reward

    uint256 public referralFeePercent ;//Referral fee percentage

    Referral public referralCa;

    // Mapping to store the whitelist for each token
    mapping(address => mapping(address => bool)) public tokenWhitelist;
    // Mapping to store the whitelist addresses for each token (array)
    mapping(address => address[]) public tokenWhitelistAddresses;
    mapping(address => mapping(address => uint256)) public addressToIndex;

    mapping(address => mapping(address => uint256)) public purchaseLimits; // Maximum baseToken a user can purchase per token
    mapping(address => mapping(address => uint256)) public purchasedAmounts; // Amount of baseToken already purchased by user per token
    mapping(address => address) public tokenToTreasury;


    // Events
    event TokenCreated (address indexed user,address indexed token,string symbol,string name,uint256 creationFee,uint256 initialBuyAmount,uint256 timestamp, string businessKey, uint256 daoId,uint256 endTime);
    event TokenBought(address indexed buyer, address indexed tokenAddress, uint256 amountIn, uint256 amountOut, uint256 fee,uint256 timestamp);
    event TokenSold(address indexed seller, address indexed tokenAddress, uint256 amountIn, uint256 amountOut,uint256 fee,uint256 timestamp);
    event TreasuryUpdated(address newTreasury);
    event FeesUpdated(uint256 newCreationFee, uint256 newLiquidityFee, uint256 newCreatorReward);
    event CreationFeeUpdated(uint256 newCreationFee);
    event LiquidityFeeUpdated(uint256 newLiquidityFee);
    event CreatorRewardUpdated(uint256 newCreatorReward);
    event FeeTransferred(address indexed payer, address indexed treasury, uint256 feeAmount, uint256 timestamp);
    event ReferralRewardPaid(address indexed user,address indexed referrer, uint256 rewardAmount, uint256 timestamp);
    event ReferralFeePercentUpdated(uint256 newReferralFeePercent);
    event WhitelistAdd(address indexed tokenAddress, address[] newAddresses,uint256[]  purchaseLimits);
    event AddressRemovedFromWhitelist(address indexed tokenAddress, address[] removedAddress);
    event TreasuryCreated(address indexed tokenAddress, address indexed treasuryAddress, address indexed creator);
    event WhitelistModelUpdated(address indexed tokenAddress, bool enabled);

    event TokenLiquidityAdded(
        address indexed token,  // Token address of the liquidity pool
        uint256 amount0,        // Amount of token0 added to the liquidity pool
        uint256 amount1,        // Amount of token1 added to the liquidity pool
        uint160 sqrtPriceX96,   // Initial price of the pool (square root of price)
        uint24 fee,             // Fee percentage for the liquidity pool
        uint256 timestamp       // Timestamp when the liquidity was added
    );

    modifier onlyTokenCreator(address tokenAddress) {
        require(msg.sender == tokenCreators[tokenAddress], "Not the token creator");
        _;
    }
    constructor() {
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        creationFee = 2e15 * 20000;//0.002
        creatorReward = 1e16 * 20000;//0.002
        liquidityFee = 1e17 * 20000;//0.1
        referralFeePercent = 5000; // 50%
    }

    function setAddresses(
        address _tokenImplementation,
        address _treasuryImplementation,
        address _baseToken,
        address _uniswapV3Factory,
        address _positionManager,
        address _swapRouter02,
        address _bondingCurveUtil,
        uint256 _feePercent,
        address payable _treasury,
        address _lockLPAddress,
        address _referralCa

    ) external onlyOwner {
        tokenImplementation = _tokenImplementation;
        treasuryImplementation = _treasuryImplementation;
        uniswapV3Factory = _uniswapV3Factory;
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter02 = ISwapRouter02(_swapRouter02);
        baseToken = IERC20(_baseToken);
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);
        feePercent = _feePercent;
        treasury = _treasury;
        lockLPAddress = _lockLPAddress;
        referralCa = Referral(_referralCa);
    }

    // Admin functions
    function setBondingCurveUtil(address _bondingCurveUtil) external onlyOwner {
        bondingCurveUtil = BondingCurveUtil(_bondingCurveUtil);
    }

    function setLockAddress(address _lockLPAddress) external onlyOwner {
        lockLPAddress = _lockLPAddress;
    }

    function setUniswapAddress(address _uniswapV3Factory,address _positionManager,address _swapRouter02) external onlyOwner {
        uniswapV3Factory = _uniswapV3Factory;
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter02 = ISwapRouter02(_swapRouter02);
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

    function setReferralCa(address _referrerCa) external onlyOwner {
        require(_referrerCa != address(0), "address null");
        referralCa = Referral(_referrerCa);
    }

    function setEndTime(uint256 _endTime,address tokenAddress) external  {
        require(tokenCreators[tokenAddress] == msg.sender,"not token creator");
        require(_endTime > block.timestamp ,"error endTime");
        endTime[tokenAddress] = _endTime;
    }

    // Token functions
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialBuyAmount,
        string memory businessKey,
        uint256 daoId,
        address referralAddress,
        uint256 _endTime,
        uint256 _fundingGoal,
        uint256 _whitelistFunding,
        bool _whitelistModel,
        address[] calldata _userAddresses,
        uint256[] calldata _purchaseLimits

    ) external payable nonReentrant returns (address) {
        require(_endTime >= block.timestamp, "endTime > block ");
        baseToken.transferFrom(msg.sender,address(this), creationFee + initialBuyAmount);
        address tokenAddress = Clones.clone(tokenImplementation);
        Token token = Token(tokenAddress);
        token.initialize(name, symbol,businessKey,daoId);
        emit TokenCreated(msg.sender,tokenAddress,symbol,name, creationFee,initialBuyAmount,block.timestamp, businessKey, daoId,_endTime);
        tokens[tokenAddress] = TokenState.FUNDING;
        tokenCreators[tokenAddress] = msg.sender;
        tokenFundingGoal[tokenAddress] = _fundingGoal;
        endTime[tokenAddress] = _endTime;
        if(_whitelistModel){
            require(_whitelistFunding <= _fundingGoal, "whitelistFunding error");
            whitelistModel[tokenAddress] = _whitelistModel;
            whitelistFunding[tokenAddress] = _whitelistFunding;
            if(_userAddresses.length > 0){
                _addToWhitelist(tokenAddress,_userAddresses,_purchaseLimits);
                emit WhitelistAdd(tokenAddress, _userAddresses,_purchaseLimits);
            }
        }
        if (creationFee > 0) {
            require( baseToken.transfer(treasury, creationFee), "Creation fee transfer to treasury failed");
            totalCreationFee += creationFee;
        }
        if (initialBuyAmount > 0) {
            _buy(tokenAddress, initialBuyAmount,referralAddress);
        }else{
            referralCa.setReferral(msg.sender,referralAddress);
        }
        CreatePoolParam memory param = _creatPoolParams(tokenAddress,INITIAL_SUPPLY,_toBuyBaseAmount(tokenAddress));
        address pool = _createLiquidityPool(param.token0,param.token1,param.fee,param.sqrtPriceX96);
        token.setPool(pool);
        return tokenAddress;
    }
    function buy(address tokenAddress,uint256 buyAmount,address referralAddress) external payable nonReentrant {
        baseToken.transferFrom(msg.sender,address(this), buyAmount);
        _buy(tokenAddress,buyAmount,referralAddress);
    }

    function _buy(address tokenAddress,uint256 buyAmount,address referralAddress) internal {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        uint256 tokenCollateral = collateral[tokenAddress];
        uint256 remainingBaseAmountNeed = _calculateRemainingBaseNeeded(tokenAddress,msg.sender);
        require(remainingBaseAmountNeed > 0,"remaining purchase base token not enough" );
        uint256 _fee = _calculateFee(buyAmount, feePercent);
        uint256 contributionWithoutFee = buyAmount - _fee;
        if (contributionWithoutFee > remainingBaseAmountNeed) {
            contributionWithoutFee = remainingBaseAmountNeed;
            _fee =(contributionWithoutFee * feePercent) / (FEE_DENOMINATOR - feePercent);
        }
        _checkPurchase(tokenAddress,msg.sender,contributionWithoutFee);
        fee += _fee;
        uint256 actualContribution = contributionWithoutFee + _fee;
        uint256 refundAmount = buyAmount > actualContribution ? buyAmount - actualContribution : 0;

        // Calculate the amount of tokens to transfer using the Bonding Curve
        Token token = Token(tokenAddress);
        uint256 amountOut = bondingCurveUtil.getAmountOut(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY,contributionWithoutFee );

        uint256 availableSupply =  token.balanceOf(address (this)) - INITIAL_SUPPLY ;
        require(amountOut <= availableSupply, "Token supply not enough");

        tokenCollateral += contributionWithoutFee;

        token.transfer(msg.sender, amountOut);

        if (tokenCollateral >= tokenFundingGoal[tokenAddress]) {
            AddLiquidityParam memory initParam =_addLiquidityParams(tokenAddress,INITIAL_SUPPLY  , 0,_toBuyBaseAmount(tokenAddress));
            _createLiquidityPool(initParam.token0,initParam.token1,initParam.fee,initParam.sqrtPriceX96);
            token.enableSendingToPool();
            uint256 tokenId = _addLiquidity(initParam);
            _transferFee(tokenAddress);
            _burnLiquidityToken( tokenId,tokenAddress);
            _createTreasury(tokenAddress,tokenCreators[tokenAddress],_toTreasuryAmount(tokenAddress),_toBuyBaseAmount(tokenAddress));
            tokens[tokenAddress] = TokenState.TRADING;
        }
        collateral[tokenAddress] = tokenCollateral;
        if(whitelistModel[tokenAddress] && tokenWhitelist[tokenAddress][msg.sender]){
            whitelistCollateral[tokenAddress] += contributionWithoutFee;
        }
        referralCa.setReferral(msg.sender,referralAddress);
        address referrer = referralCa.getReferrer(msg.sender); // Get the referrer address

        if (referrer != address(0)) {
            // Referral reward logic
            uint256 referralReward = (_fee * referralFeePercent) / FEE_DENOMINATOR; // Calculate the referral reward
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
        purchasedAmounts[tokenAddress][msg.sender] += contributionWithoutFee;
        emit TokenBought(msg.sender, tokenAddress, actualContribution, amountOut, _fee, block.timestamp);
    }

    function sell(address tokenAddress,address referralAddress, uint256 amount) external nonReentrant {
        require(endTime[tokenAddress] < block.timestamp && tokens[tokenAddress] == TokenState.FUNDING, "Token not in refund state");
        require(amount > 0, "Amount must be greater than zero");
        Token token = Token(tokenAddress);
        uint256 receivedBaseAmount = bondingCurveUtil.getFundsReceived(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY,amount);
        require(receivedBaseAmount > 0, "Insufficient base token received after fee deduction");
        collateral[tokenAddress] -= receivedBaseAmount;

        token.transferFrom(msg.sender,address(this), amount);

        require(baseToken.transfer(msg.sender, receivedBaseAmount), "baseToken send failed");

         referralCa.setReferral(msg.sender,referralAddress);

        emit TokenSold(msg.sender, tokenAddress, amount, receivedBaseAmount,0, block.timestamp);
    }

    function _createLiquidityPool( address token0,address token1,uint24 _uniV3fee,uint160 sqrtPriceX96) internal returns (address) {
       address pool =  positionManager.createAndInitializePoolIfNecessary(token0,token1
           ,_uniV3fee,sqrtPriceX96);
        require(pool != address(0),"create pool error " );
        return pool;
    }

    function _addLiquidityParams(address tokenAddress, uint256 tokenAmount, uint256 baseAmount,uint256 uinBaseAmount ) internal view returns (AddLiquidityParam memory addLiquidityParam) {

        uint256 addLqBaseAmount = baseAmount ;

        // Assign token0 and token1 based on the comparison of tokenAddress and baseToken
        addLiquidityParam.token0 = tokenAddress < address(baseToken) ? tokenAddress : address(baseToken);
        addLiquidityParam.token1 = tokenAddress < address(baseToken) ? address(baseToken) : tokenAddress;

        // Assign amounts for token0 and token1
        addLiquidityParam.amount0 = tokenAddress < address(baseToken) ? tokenAmount : addLqBaseAmount;
        addLiquidityParam.amount1 = tokenAddress < address(baseToken) ? addLqBaseAmount : tokenAmount;
        addLiquidityParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        addLiquidityParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,tokenAmount,uinBaseAmount);
        int24 tickSpacing = IUniswapV3Factory(uniswapV3Factory).feeAmountTickSpacing(uniV3fee);
        require(tickSpacing != 0 , "Invalid tick");
        (int24 _tickLower,int24 _tickUpper) = bondingCurveUtil.getTick(tokenAddress,address(baseToken),addLiquidityParam.sqrtPriceX96,tickSpacing);
        // Return the constructed InitParam struct
        addLiquidityParam.tickLower = _tickLower;
        addLiquidityParam.tickUpper = _tickUpper;
        return addLiquidityParam;
    }

    function _creatPoolParams(address tokenAddress,uint256 _tokenAmount,uint256 _baseAmount ) internal view returns (CreatePoolParam memory createPoolParam) {
        // Assign token0 and token1 based on the comparison of tokenAddress and baseToken
        createPoolParam.token0 = tokenAddress < address(baseToken) ? tokenAddress : address(baseToken);
        createPoolParam.token1 = tokenAddress < address(baseToken) ? address(baseToken) : tokenAddress;

        createPoolParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        createPoolParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,_tokenAmount,_baseAmount);

        // Return the constructed InitParam struct
        return createPoolParam;
    }

    function _initSqrtPriceX96(address _tokenAddress,uint256 tokenAmount,uint256 baseAmount) internal view returns(uint160)  {

         return _tokenAddress < address(baseToken) ? bondingCurveUtil.calculateSqrtPriceX96(tokenAmount,baseAmount)
              : bondingCurveUtil.calculateSqrtPriceX96(baseAmount,tokenAmount);
    }

    function _addLiquidity(AddLiquidityParam memory initParam) internal returns (uint256) {

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: initParam.token0,
            token1: initParam.token1,
            fee: initParam.fee, // 1%
            tickLower: initParam.tickLower,
            tickUpper: initParam.tickUpper,
            amount0Desired: initParam.amount0,
            amount1Desired: initParam.amount1,
            amount0Min: 0,
            amount1Min:0,
            recipient: address(this),
            deadline: block.timestamp + 30
        });
        if (initParam.token0 == address(baseToken)) {
            IERC20(initParam.token1).approve(address(positionManager), initParam.amount1);
        }else if (initParam.token1 == address(baseToken)) {
            IERC20(initParam.token0).approve(address(positionManager), initParam.amount0);
        }

        (uint256 tokenId,  ,uint256 amount0,uint256 amount1  ) = positionManager.mint(params);

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

    function _transferFee(address tokenAddress) internal {
        (uint256 _liquidityFee, uint256 _creatorReward) = _getTransferFee(tokenAddress);
        if (_liquidityFee > 0) {
            require(baseToken.transfer(treasury,_liquidityFee), "Liquidity fee transfer to treasury failed");
            totalLiquidityFee += _liquidityFee;
        }

        if (creatorReward > 0) {
            require(baseToken.transfer(tokenCreators[tokenAddress],_creatorReward), "Creator reward transfer failed");
            totalCreatorReward += _creatorReward;
        }
    }

    function _getTransferFee(address tokenAddress) internal view returns (uint256 _liquidityFee, uint256 _creatorReward) {
        uint256 _tokenFundingGoal = tokenFundingGoal[tokenAddress];

        uint256 fundingGoalPercentage = (_tokenFundingGoal * 5) / 100;

        _liquidityFee = liquidityFee > fundingGoalPercentage ? fundingGoalPercentage : liquidityFee;

        _creatorReward = _liquidityFee / 10;

        return (_liquidityFee, _creatorReward);
    }

    function _burnLiquidityToken(uint256 tokenId,address tokenAddress) internal {
        // Transfer the LP token (Uniswap V3 liquidity token) to the lock address
        positionManager.safeTransferFrom(address(this), lockLPAddress, tokenId);

        // Trigger the initializer function in the lock contract to lock the LP token
        ILocker(lockLPAddress).add(tokenAddress,tokenId,tokenCreators[tokenAddress]);
    }

    function _createTreasury(address tokenAddress, address creator,uint256 baseAmount,uint256 buyAmount) internal returns (address ) {
        require(tokenAddress != address(0), "Invalid token address");
        require(creator != address(0), "Invalid creator address");

        address newTreasuryAddress = Clones.clone(treasuryImplementation);
        address payable payableNewTreasuryAddress = payable(newTreasuryAddress);

        Treasury newTreasury = Treasury(payableNewTreasuryAddress);
        newTreasury.initialize(creator, tokenAddress);
        tokenToTreasury[tokenAddress] = newTreasuryAddress;

        if (baseAmount > 0) {
            require(baseToken.transfer(address(newTreasury),baseAmount), "Failed to send baseToken to Treasury");
        }

        baseToken.approve(address(swapRouter02), buyAmount);
        swapRouter02.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(baseToken),
                tokenOut: tokenAddress,
                fee: uniV3fee,
                recipient: tokenToTreasury[tokenAddress],
                amountIn: buyAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        emit TreasuryCreated(tokenAddress, newTreasuryAddress, creator);

        return newTreasuryAddress;
    }

    function getAmountOut(address tokenAddress, uint256 baseAmount) external view returns (uint256 tokenAmount) {
        tokenAmount = bondingCurveUtil.getAmountOut(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY
            ,baseAmount - _calculateFee(baseAmount, feePercent));
        if( tokenAmount > FUNDING_SUPPLY){
            tokenAmount = FUNDING_SUPPLY;
        }
    }

    function getAmountOutByCreate(uint256 _tokenFundingGoal,uint256 baseAmount) external view returns (uint256 tokenAmount) {
        tokenAmount = bondingCurveUtil.getAmountOut(_tokenFundingGoal, FUNDING_SUPPLY
            ,baseAmount - _calculateFee(baseAmount, feePercent));
        if( tokenAmount > FUNDING_SUPPLY){
            tokenAmount = FUNDING_SUPPLY;
        }
    }

    function getFundsReceived(address tokenAddress, uint256 deltaToken) external view returns (uint256 received) {
        received = bondingCurveUtil.getFundsReceived(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY, deltaToken);
        return received;
    }

    function _calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / FEE_DENOMINATOR;
    }

    function withdrawWETH(uint256 amount,address receipt) external onlyOwner {
        require(amount <= IERC20(baseToken).balanceOf(address(this)), "Insufficient baseToken balance");
        IERC20(baseToken).transfer(receipt, amount);
    }

    function fundingGoal(address _tokenAddress) external view override returns (uint256){
        return tokenFundingGoal[_tokenAddress];
    }

    function getCurrentPrice(address tokenAddress) external view override returns (uint256 ) {
        return bondingCurveUtil.getCurrentPrice(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY);
    }
    function getProgress(address tokenAddress)  external view  override returns (bool whiteListModel,uint256 raised, uint256 target,uint256 beeCollateral,uint256 beeFunding)  {
        if(tokens[tokenAddress] == TokenState.TRADING){
            return (whiteListModel,tokenFundingGoal[tokenAddress],tokenFundingGoal[tokenAddress],whitelistCollateral[tokenAddress],whitelistFunding[tokenAddress]);
        }
        return (whitelistModel[tokenAddress], collateral[tokenAddress],tokenFundingGoal[tokenAddress],whitelistCollateral[tokenAddress],whitelistFunding[tokenAddress]);
    }
    function getState(address tokenAddress) external view override returns (uint8 _state){
        if(tokens[tokenAddress] == TokenState.FUNDING && block.timestamp > endTime[tokenAddress]){
            _state = uint8(TokenState.FAILED);
        }else{
            _state = uint8(tokens[tokenAddress]);
        }
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

    function getEnTime(address tokenAddress) external view override returns (uint256){
        return endTime[tokenAddress];
    }


    function authorizeUpgrade(address newImplementation) public {
        _authorizeUpgrade(newImplementation);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}


    function addToTokenWhitelist(address tokenAddress, address[] calldata _userAddresses, uint256[] calldata _purchaseLimits) external nonReentrant onlyTokenCreator(tokenAddress) {
        require(whitelistModel[tokenAddress],"not whiteList model");
        _addToWhitelist(tokenAddress, _userAddresses, _purchaseLimits);
        emit WhitelistAdd(tokenAddress, _userAddresses,_purchaseLimits);
    }

    function checkPurchase(address tokenAddress, address user,uint256 amount) external view  returns(bool){
        return _checkPurchase(tokenAddress,user,amount);
    }

    function _checkPurchase(address tokenAddress,address user, uint256 amount) internal view returns(bool){
        require(endTime[tokenAddress] >= block.timestamp,"ended");
        if(!whitelistModel[tokenAddress] || !tokenWhitelist[tokenAddress][user]){
            return true;
        }
        uint256 remainingLimit = purchaseLimits[tokenAddress][user] - purchasedAmounts[tokenAddress][user];
        require(amount <= remainingLimit, "Purchase amount exceeds remaining limit");
        uint256 _whitelistFunding = whitelistFunding[tokenAddress];
        uint256 _whitelistCollateral = whitelistCollateral[tokenAddress];
        require(_whitelistFunding >= _whitelistCollateral + amount,"whitelist quota not enough" );
        return true;
    }


    function removeFromTokenWhitelist(address tokenAddress,address[] calldata removeAddresses) external nonReentrant onlyTokenCreator(tokenAddress) {

        require(removeAddresses.length > 0, "No addresses provided");

        address[] storage whitelist = tokenWhitelistAddresses[tokenAddress];

        for (uint i = 0; i < removeAddresses.length; i++) {
            address removeAddress = removeAddresses[i];

            if (!tokenWhitelist[tokenAddress][removeAddress]) {
                continue;
            }

            uint256 index = addressToIndex[tokenAddress][removeAddress];
            uint256 lastIndex = whitelist.length - 1;

            // 删除白名单映射
            delete tokenWhitelist[tokenAddress][removeAddress];
            delete purchaseLimits[tokenAddress][removeAddress];
            delete purchasedAmounts[tokenAddress][removeAddress];

            if (index != lastIndex) {
                address lastAddress = whitelist[lastIndex];
                whitelist[index] = lastAddress;
                addressToIndex[tokenAddress][lastAddress] = index;
            }

            whitelist.pop();
            delete addressToIndex[tokenAddress][removeAddress];
        }
        if(removeAddresses.length > 0){
            emit AddressRemovedFromWhitelist(tokenAddress, removeAddresses);
        }

    }

    function getWhitelist(address tokenAddress) external view returns (address[] memory) {
        return tokenWhitelistAddresses[tokenAddress];
    }

    function getWhitelistLength(address tokenAddress) external view returns (uint256 ) {
        return tokenWhitelistAddresses[tokenAddress].length;
    }

    function getWhitelistByRange(address tokenAddress, uint256 start, uint256 end) external view returns (address[] memory) {
        address[] storage whitelist = tokenWhitelistAddresses[tokenAddress];
        require(start < whitelist.length, "Start index out of bounds");
        require(end < whitelist.length, "End index out of bounds");
        require(start <= end, "Start index must be less than or equal to end index");

        uint256 length = end - start + 1;
        address[] memory whitelistSubset = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            whitelistSubset[i] = whitelist[start + i];
        }

        return whitelistSubset;
    }

    function getPurchaseDetails(address tokenAddress, address user) external view returns (uint256 limit, uint256 purchased) {
        return (purchaseLimits[tokenAddress][user], purchasedAmounts[tokenAddress][user]);
    }

    function _clearWhitelist(address tokenAddress) private {
        address[] storage whitelist = tokenWhitelistAddresses[tokenAddress];

        for (uint i = 0; i < whitelist.length; i++) {
            address oldAddress = whitelist[i];
            delete tokenWhitelist[tokenAddress][oldAddress];
            delete purchaseLimits[tokenAddress][oldAddress];
            delete addressToIndex[tokenAddress][oldAddress];
        }

        delete tokenWhitelistAddresses[tokenAddress];
    }

    function _addToWhitelist(address tokenAddress, address[] calldata _newAddresses, uint256[] calldata _purchaseLimits) private {
        require(_newAddresses.length > 0, "Empty address");
        require(_newAddresses.length == _purchaseLimits.length, "Addresses and purchase limits arrays must have the same length");

        for (uint i = 0; i < _newAddresses.length; i++) {
            require(_purchaseLimits[i] <= whitelistFunding[tokenAddress],"purchase limits error");
                address newAddress = _newAddresses[i];
                if(!tokenWhitelist[tokenAddress][newAddress]){
                    tokenWhitelistAddresses[tokenAddress].push(newAddress);
                    addressToIndex[tokenAddress][newAddress] = tokenWhitelistAddresses[tokenAddress].length - 1;
                }
                tokenWhitelist[tokenAddress][newAddress] = true;
                purchaseLimits[tokenAddress][newAddress] = _purchaseLimits[i];
            }
    }

    function _toBuyBaseAmount(address _tokenAddress) private view  returns(uint256 _uniBaseAmount){
        _uniBaseAmount = tokenFundingGoal[_tokenAddress] * 10/100;
    }

    function _toTreasuryAmount(address _tokenAddress) private view returns(uint256 _treasuryBaseAmount){
        _treasuryBaseAmount = tokenFundingGoal[_tokenAddress] * 90/100;
        (uint256 _liquidityFee, uint256 _creatorReward) = _getTransferFee(_tokenAddress);
        _treasuryBaseAmount = _treasuryBaseAmount - _liquidityFee - _creatorReward;
    }

    function calculateRemainingBaseNeeded(address tokenAddress, address user) external override view returns (uint256) {
       return _calculateRemainingBaseNeeded(tokenAddress,user);
    }

    function _calculateRemainingBaseNeeded(address tokenAddress, address user) internal  view returns (uint256) {
        uint256 remainingBaseNeeded ;
        uint256 tokenCollateral = collateral[tokenAddress];
        if(whitelistModel[tokenAddress]){
            if(tokenWhitelist[tokenAddress][user]){
                remainingBaseNeeded = whitelistFunding[tokenAddress] - whitelistCollateral[tokenAddress];
                uint256 _purchaseLimits = purchaseLimits[tokenAddress][user];
                uint256 _purchaseAmounts = purchasedAmounts[tokenAddress][user];
                uint256 userRemainingBaseAmount = _purchaseLimits > _purchaseAmounts ? _purchaseLimits - _purchaseAmounts : 0;
                remainingBaseNeeded = remainingBaseNeeded > userRemainingBaseAmount ? userRemainingBaseAmount : remainingBaseNeeded;
            }else{
                remainingBaseNeeded = (tokenFundingGoal[tokenAddress] - whitelistFunding[tokenAddress]) - (tokenCollateral - whitelistCollateral[tokenAddress]);
            }
        }else {
            remainingBaseNeeded = tokenFundingGoal[tokenAddress] - tokenCollateral;
        }
        return remainingBaseNeeded;
    }


}