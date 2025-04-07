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
import {IWETH} from "./interfaces/IWETH.sol";
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

    mapping(address => uint256) public collateral; // Collateral (ETH)
    mapping(address => uint256) public whitelistCollateral; // whitelistCollateral (ETH)

    mapping(address => uint256) public tokenFundingGoal; // Target ETH for funding phase
    mapping(address => uint256) public whitelistFunding; // whitelist Target ETH for funding phase
    mapping(address => uint256) public endTime; // phase end time
    mapping(address => bool) public whitelistModel; // phase end time


    address public uniswapV3Factory; // Uniswap V3 Factory address
    INonfungiblePositionManager public positionManager; // Uniswap V3 Position Manager address
    ISwapRouter02 public swapRouter02; // Uniswap V3 Position Manager address
    address public WETH;  // WETH address
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

    mapping(address => mapping(address => uint256)) public purchaseLimits; // Maximum ETH a user can purchase per token
    mapping(address => mapping(address => uint256)) public purchasedAmounts; // Amount of ETH already purchased by user per token
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
        creationFee = 2e15;//0.002
        creatorReward = 1e16;//0.002
        liquidityFee = 1e17;//0.1
        referralFeePercent = 5000; // 50%
    }

    function setAddresses(
        address _tokenImplementation,
        address _treasuryImplementation,
        address _WETH,
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
        WETH = _WETH;
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
        require(msg.value >= creationFee + initialBuyAmount, "Insufficient ETH sent for token creation");
        require(_endTime >= block.timestamp, "end time > block ");
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
            _buy(tokenAddress, initialBuyAmount,referralAddress,initialBuyAmount);
        }else{
            referralCa.setReferral(msg.sender,referralAddress);
        }
        CreatePoolParam memory param = _creatPoolParams(tokenAddress,INITIAL_SUPPLY,_toBuyEthAmount(tokenAddress));
        address pool = _createLiquidityPool(param.token0,param.token1,param.fee,param.sqrtPriceX96);
        token.setPool(pool);
        return tokenAddress;
    }
    function buy(address tokenAddress,uint256 ethAmount,address referralAddress) external payable nonReentrant {
        _buy(tokenAddress,ethAmount,referralAddress,msg.value);
    }

    function _buy(address tokenAddress,uint256 buyAmount,address referralAddress,uint256 receiveEth) internal {
        require(tokens[tokenAddress] == TokenState.FUNDING, "Token not in funding phase");
        require(msg.value >= buyAmount, "ETH not enough");
        uint256 valueToBuy = buyAmount;
        uint256 tokenCollateral = collateral[tokenAddress];
        uint256 remainingEthNeeded = _calculateRemainingEthNeeded(tokenAddress,msg.sender);
        require(remainingEthNeeded > 0,"remaining purchase eth not enough" );
        uint256 _fee = _calculateFee(valueToBuy, feePercent);
        uint256 contributionWithoutFee = valueToBuy - _fee;
        if (contributionWithoutFee > remainingEthNeeded) {
            contributionWithoutFee = remainingEthNeeded;
            _fee =(contributionWithoutFee * feePercent) / (FEE_DENOMINATOR - feePercent);
        }
        _checkPurchase(tokenAddress,msg.sender,contributionWithoutFee);
        fee += _fee;
        uint256 actualContribution = contributionWithoutFee + _fee;
        uint256 refundAmount = receiveEth > actualContribution ? receiveEth - actualContribution : 0;

        // Calculate the amount of tokens to transfer using the Bonding Curve
        Token token = Token(tokenAddress);
        uint256 amountOut = bondingCurveUtil.getAmountOut(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY,contributionWithoutFee );

        uint256 availableSupply =  token.balanceOf(address (this)) - INITIAL_SUPPLY ;
        require(amountOut <= availableSupply, "Token supply not enough");

        tokenCollateral += contributionWithoutFee;

        token.transfer(msg.sender, amountOut);

        if (tokenCollateral >= tokenFundingGoal[tokenAddress]) {
            AddLiquidityParam memory initParam =_addLiquidityParams(tokenAddress,INITIAL_SUPPLY  , 0,_toBuyEthAmount(tokenAddress));
            _createLiquidityPool(initParam.token0,initParam.token1,initParam.fee,initParam.sqrtPriceX96);
            token.enableSendingToPool();
            uint256 tokenId = _addLiquidity(initParam);
            _transferFee(tokenAddress);
            _burnLiquidityToken( tokenId,tokenAddress);
            _createTreasury(tokenAddress,tokenCreators[tokenAddress],_toTreasuryAmount(tokenAddress),_toBuyEthAmount(tokenAddress));
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
        purchasedAmounts[tokenAddress][msg.sender] += contributionWithoutFee;
        emit TokenBought(msg.sender, tokenAddress, actualContribution, amountOut, _fee, block.timestamp);
    }

    function sell(address tokenAddress,address referralAddress, uint256 amount) external nonReentrant {
        require(endTime[tokenAddress] < block.timestamp && tokens[tokenAddress] == TokenState.FUNDING, "Token not in refund state");
        require(amount > 0, "Amount must be greater than zero");

        Token token = Token(tokenAddress);
        uint256 receivedETH = bondingCurveUtil.getFundsReceived(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY,amount);
        collateral[tokenAddress] -= receivedETH;
        require(receivedETH > 0, "Insufficient ETH received after fee deduction");

        token.transferFrom(msg.sender,address(this), amount);
        (bool success, ) = msg.sender.call{value: receivedETH}(new bytes(0));
        require(success, "ETH send failed");

         referralCa.setReferral(msg.sender,referralAddress);

        emit TokenSold(msg.sender, tokenAddress, amount, receivedETH,0, block.timestamp);
    }

    function _createLiquidityPool( address token0,address token1,uint24 _uniV3fee,uint160 sqrtPriceX96) internal returns (address) {
       address pool =  positionManager.createAndInitializePoolIfNecessary(token0,token1
           ,_uniV3fee,sqrtPriceX96);
        require(pool != address(0),"create pool error " );
        return pool;
    }

    function _addLiquidityParams(address tokenAddress, uint256 tokenAmount, uint256 ethAmount,uint256 uinEthAmount ) internal view returns (AddLiquidityParam memory addLiquidityParam) {

        uint256 addLqEthAmount = ethAmount ;

        // Assign token0 and token1 based on the comparison of tokenAddress and WETH
        addLiquidityParam.token0 = tokenAddress < WETH ? tokenAddress : WETH;
        addLiquidityParam.token1 = tokenAddress < WETH ? WETH : tokenAddress;

        // Assign amounts for token0 and token1
        addLiquidityParam.amount0 = tokenAddress < WETH ? tokenAmount : addLqEthAmount;
        addLiquidityParam.amount1 = tokenAddress < WETH ? addLqEthAmount : tokenAmount;
        addLiquidityParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        addLiquidityParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,tokenAmount,uinEthAmount);
        int24 tickSpacing = IUniswapV3Factory(uniswapV3Factory).feeAmountTickSpacing(uniV3fee);
        require(tickSpacing != 0 , "Invalid tick");
        (int24 _tickLower,int24 _tickUpper) = bondingCurveUtil.getTick(tokenAddress,WETH,addLiquidityParam.sqrtPriceX96,tickSpacing);
        // Return the constructed InitParam struct
        addLiquidityParam.tickLower = _tickLower;
        addLiquidityParam.tickUpper = _tickUpper;
        return addLiquidityParam;
    }

    function _creatPoolParams(address tokenAddress,uint256 _tokenAmount,uint256 _ethAmount ) internal view returns (CreatePoolParam memory createPoolParam) {
        // Assign token0 and token1 based on the comparison of tokenAddress and WETH
        createPoolParam.token0 = tokenAddress < WETH ? tokenAddress : WETH;
        createPoolParam.token1 = tokenAddress < WETH ? WETH : tokenAddress;

        createPoolParam.fee = uniV3fee;
        // Corrected calculation of sqrtPriceX96 based on the token amounts
        createPoolParam.sqrtPriceX96 = _initSqrtPriceX96(tokenAddress,_tokenAmount,_ethAmount);

        // Return the constructed InitParam struct
        return createPoolParam;
    }

    function _initSqrtPriceX96(address _tokenAddress,uint256 tokenAmount,uint256 ethAmount) internal view returns(uint160)  {

         return _tokenAddress < WETH ? bondingCurveUtil.calculateSqrtPriceX96(tokenAmount,ethAmount)
              : bondingCurveUtil.calculateSqrtPriceX96(ethAmount,tokenAmount);
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
        if (initParam.token0 == WETH) {
            IERC20(initParam.token1).approve(address(positionManager), initParam.amount1);
        }else if (initParam.token1 == WETH) {
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
            (bool sentLiquidityFee, ) = treasury.call{value: _liquidityFee}("");
            require(sentLiquidityFee, "Liquidity fee transfer to treasury failed");
            totalLiquidityFee += _liquidityFee;
        }

        if (creatorReward > 0) {
            (bool sentCreatorReward, ) = payable(tokenCreators[tokenAddress]).call{value: _creatorReward}("");
            require(sentCreatorReward, "Creator reward transfer failed");
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

    function _createTreasury(address tokenAddress, address creator,uint256 ethAmount,uint256 buyAmount) internal returns (address ) {
        require(tokenAddress != address(0), "Invalid token address");
        require(creator != address(0), "Invalid creator address");

        address newTreasuryAddress = Clones.clone(treasuryImplementation);
        address payable payableNewTreasuryAddress = payable(newTreasuryAddress);

        Treasury newTreasury = Treasury(payableNewTreasuryAddress);
        newTreasury.initialize(creator, tokenAddress);
        tokenToTreasury[tokenAddress] = newTreasuryAddress;

        if (ethAmount > 0) {
            (bool success, ) = payable(address(newTreasury)).call{value: ethAmount}("");
            require(success, "Failed to send ETH to Treasury");
        }
        swapRouter02.exactInputSingle{value: buyAmount}(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: WETH,
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

    function getAmountOut(address tokenAddress, uint256 ethAmount) external view returns (uint256 tokenAmount) {
        tokenAmount = bondingCurveUtil.getAmountOut(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY
            ,ethAmount - _calculateFee(ethAmount, feePercent));
        if( tokenAmount > FUNDING_SUPPLY){
            tokenAmount = FUNDING_SUPPLY;
        }
    }

    function getAmountOutByCreate(uint256 _tokenFundingGoal,uint256 ethAmount) external view returns (uint256 tokenAmount) {
        tokenAmount = bondingCurveUtil.getAmountOut(_tokenFundingGoal, FUNDING_SUPPLY
            ,ethAmount - _calculateFee(ethAmount, feePercent));
        if( tokenAmount > FUNDING_SUPPLY){
            tokenAmount = FUNDING_SUPPLY;
        }
    }

    function getFundsReceived(address tokenAddress, uint256 deltaToken) external view returns (uint256 ethReceived) {
        ethReceived = bondingCurveUtil.getFundsReceived(tokenFundingGoal[tokenAddress], FUNDING_SUPPLY, deltaToken);
        return ethReceived;
    }

    function _calculateFee(uint256 _amount, uint256 _feePercent) internal pure returns (uint256) {
        return (_amount * _feePercent) / FEE_DENOMINATOR;
    }

    function withdrawWETH(uint256 amount,address receipt) external onlyOwner {
        require(amount <= IERC20(WETH).balanceOf(address(this)), "Insufficient WETH balance");
        IERC20(WETH).transfer(receipt, amount);
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

    function _toBuyEthAmount(address _tokenAddress) private view  returns(uint256 _uniEthAmount){
        _uniEthAmount = tokenFundingGoal[_tokenAddress] * 10/100;
    }

    function _toTreasuryAmount(address _tokenAddress) private view returns(uint256 _treasuryEthAmount){
        _treasuryEthAmount = tokenFundingGoal[_tokenAddress] * 90/100;
        (uint256 _liquidityFee, uint256 _creatorReward) = _getTransferFee(_tokenAddress);
        _treasuryEthAmount = _treasuryEthAmount - _liquidityFee - _creatorReward;
    }

    function calculateRemainingEthNeeded(address tokenAddress, address user) external override view returns (uint256) {
       return _calculateRemainingEthNeeded(tokenAddress,user);
    }

    function _calculateRemainingEthNeeded(address tokenAddress, address user) internal  view returns (uint256) {
        uint256 remainingEthNeeded ;
        uint256 tokenCollateral = collateral[tokenAddress];
        if(whitelistModel[tokenAddress]){
            if(tokenWhitelist[tokenAddress][user]){
                remainingEthNeeded = whitelistFunding[tokenAddress] - whitelistCollateral[tokenAddress];
                uint256 _purchaseLimits = purchaseLimits[tokenAddress][user];
                uint256 _purchaseAmounts = purchasedAmounts[tokenAddress][user];
                uint256 userRemainingEth = _purchaseLimits > _purchaseAmounts ? _purchaseLimits - _purchaseAmounts : 0;
                remainingEthNeeded = remainingEthNeeded > userRemainingEth ? userRemainingEth : remainingEthNeeded;
            }else{
                remainingEthNeeded = (tokenFundingGoal[tokenAddress] - whitelistFunding[tokenAddress]) - (tokenCollateral - whitelistCollateral[tokenAddress]);
            }
        }else {
            remainingEthNeeded = tokenFundingGoal[tokenAddress] - tokenCollateral;
        }
        return remainingEthNeeded;
    }


}