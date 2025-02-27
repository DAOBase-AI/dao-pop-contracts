// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ILocker} from "./interfaces/ILocker.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title LpLocker
/// @dev A contract to lock LP tokens, collect fees from Uniswap V3 positions, and distribute them to treasury, creators, and inviter.
contract LpLocker is ILocker, Ownable, IERC721Receiver,ReentrancyGuardUpgradeable {
    using SafeMath for uint256;

    // Events declaration
    event FeesClaimed(address indexed claimer, uint256 amount0, uint256 amount1);
    event LockDurationUpdated(uint256 tokenId, uint256 newDuration);
    event Received(address indexed from, uint256 tokenId);
    event FeeDistributionUpdated(uint256 treasuryFee, uint256 creatorFee, uint256 inviterFee);
    event AddressesUpdated(address indexed treasury, address indexed inviter, address indexed positionManagerAddress, address bondingCurveAddress);
    event TokenReleased(uint256 indexed tokenId, address indexed owner);

    // Structure to store information about the locked token
    struct TokenLockInfo {
        address token;       // The address of the token
        uint256 lockEndTime;   // The end time of the lock period for the token
        address creator;       // The creator of the token
    }

    // Constant representing the lock duration of 100 years in seconds
    uint256 public constant lockDuration = 100 * 365 * 24 * 60 * 60;  // 100 years in seconds
    uint256 public constant FEE_DENOMINATOR = 1000;  // Fee distribution denominator, used for percentage calculation

    // Mapping to store the lock information for each tokenId
    mapping(uint256 => TokenLockInfo) public tokenLocks;

    // Mapping to store token address and associated tokenId
    mapping(address => uint256) public tokenAddressToTokenId;

    // Fee distribution percentages for treasury, creator, and inviter
    uint256 public treasuryFeePercentage; // Percentage of fees allocated to the treasury
    uint256 public creatorFeePercentage;  // Percentage of fees allocated to the creator
    uint256 public inviterFeePercentage;  // Percentage of fees allocated to the inviter

    // Addresses for treasury, inviter, position manager, and bonding curve
    address public treasury;  // Treasury address
    address public inviter;   // Inviter commission address
    address public positionManagerAddress; // Uniswap V3 Position Manager contract address
    address public bondingCurveAddress; // Bonding Curve contract address

    // Array to store all locked tokenIds
    uint256[] public tokenIds;
    // Mapping to check if a tokenId is already locked (to prevent duplicates)
    mapping(uint256 => bool) public isTokenLocked;

    // Modifier to restrict access to either the owner or the bonding curve contract
    modifier onlyOwnerOrBondingCurve() {
        require(msg.sender == owner() || msg.sender == bondingCurveAddress, "Caller is not the owner or the bonding curve");
        _;
    }

    // Constructor to initialize the default fee distribution percentages
    constructor() {
        treasuryFeePercentage = 800;  // 50% => 500
        creatorFeePercentage = 200;   // 30% => 300
        inviterFeePercentage = 0;   // 20% => 200
    }

    // Function to set fee distribution percentages, making sure the total is 1000 (100%)
    function setFeeDistribution(
        uint256 _treasuryFeePercentage,
        uint256 _creatorFeePercentage,
        uint256 _inviterFeePercentage
    ) external onlyOwner {
        require(
            _treasuryFeePercentage.add(_creatorFeePercentage).add(_inviterFeePercentage) == 1000,
            "Total fee percentage must be 1000"
        );

        treasuryFeePercentage = _treasuryFeePercentage;
        creatorFeePercentage = _creatorFeePercentage;
        inviterFeePercentage = _inviterFeePercentage;

        emit FeeDistributionUpdated(
            treasuryFeePercentage,
            creatorFeePercentage,
            inviterFeePercentage
        );
    }

    // Function to set four important contract addresses in a single call (treasury, inviter, position manager, and bonding curve)
    function setAddresses(
        address _treasury,
        address _inviter,
        address _positionManagerAddress,
        address _bondingCurveAddress
    ) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        require(_inviter != address(0), "Invalid inviter address");
        require(_positionManagerAddress != address(0), "Invalid position manager address");
        require(_bondingCurveAddress != address(0), "Invalid bonding curve address");

        treasury = _treasury;
        inviter = _inviter;
        positionManagerAddress = _positionManagerAddress;
        bondingCurveAddress = _bondingCurveAddress;

        emit AddressesUpdated(treasury, inviter, positionManagerAddress, bondingCurveAddress);
    }

    // Function to add the LP token lock, setting the creator and lock end time
    function add(address token, uint256 tokenId, address creator) override external onlyOwnerOrBondingCurve {
        TokenLockInfo storage lockInfo = tokenLocks[tokenId];
        require(lockInfo.creator == address(0), "LP token already initialized");
        lockInfo.creator = creator;
        lockInfo.token = token;
        lockInfo.lockEndTime = block.timestamp + lockDuration; // Set the lock end time to 100 years from now
        tokenAddressToTokenId[token] = tokenId; // Store the tokenId associated with the token address

        // Add tokenId to the array if it's not already recorded
        if (!isTokenLocked[tokenId]) {
            tokenIds.push(tokenId);
            isTokenLocked[tokenId] = true;
        }

        emit Received(msg.sender, tokenId);
    }

    function claimFees(uint256 tokenId) external nonReentrant {
        _claimFees(tokenId);
    }
    // Function to claim fees for multiple tokenIds in a single transaction
    function batchClaimFees(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length > 0, "No tokenIds provided");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            _claimFees(tokenId);
        }
    }

    // Function to claim fees from Uniswap V3 Position Manager and distribute them based on fee percentages
    function _claimFees(uint256 tokenId) internal {
        TokenLockInfo memory lockInfo = tokenLocks[tokenId];

        // Ensure that the token has been initialized
        require(lockInfo.creator != address(0), "Token is not initialized");

        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionManagerAddress);

        // Collect the fees from Uniswap V3
        (uint256 feeAmount0, uint256 feeAmount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Ensure that fees are available for collection
        require(feeAmount0 > 0 || feeAmount1 > 0, "No fees available for collection");

        // Ensure that the fee percentages are valid (greater than 0)
        require(treasuryFeePercentage >= 0 || creatorFeePercentage >= 0 || inviterFeePercentage >= 0, "Invalid fee distribution percentages");

        // Calculate the amounts to be transferred to each address based on the fee percentages
        uint256 treasuryAmount0 = feeAmount0.mul(treasuryFeePercentage).div(FEE_DENOMINATOR);
        uint256 creatorAmount0 = feeAmount0.mul(creatorFeePercentage).div(FEE_DENOMINATOR);
        uint256 inviterAmount0 = feeAmount0.mul(inviterFeePercentage).div(FEE_DENOMINATOR);

        uint256 treasuryAmount1 = feeAmount1.mul(treasuryFeePercentage).div(FEE_DENOMINATOR);
        uint256 creatorAmount1 = feeAmount1.mul(creatorFeePercentage).div(FEE_DENOMINATOR);
        uint256 inviterAmount1 = feeAmount1.mul(inviterFeePercentage).div(FEE_DENOMINATOR);

        // Get the token addresses from the Uniswap V3 position
        (, , address token0, address token1) = positionManager.positions(tokenId);

        // Ensure the token addresses are valid
        require(token0 != address(0) && token1 != address(0), "Invalid token addresses");

        IERC20 feeToken0 = IERC20(token0); // Token0 (first token of the Uniswap pair)
        IERC20 feeToken1 = IERC20(token1); // Token1 (second token of the Uniswap pair)

        // Transfer the calculated fees to the respective addresses
        if (treasuryAmount0 > 0) {
            feeToken0.transfer(treasury, treasuryAmount0);
        }
        if (creatorAmount0 > 0) {
            feeToken0.transfer(lockInfo.creator, creatorAmount0); // Transfer to the creator
        }
        if (inviterAmount0 > 0) {
            feeToken0.transfer(inviter, inviterAmount0);
        }

        if (treasuryAmount1 > 0) {
            feeToken1.transfer(treasury, treasuryAmount1);
        }
        if (creatorAmount1 > 0) {
            feeToken1.transfer(lockInfo.creator, creatorAmount1); // Transfer to the creator
        }
        if (inviterAmount1 > 0) {
            feeToken1.transfer(inviter, inviterAmount1);
        }

        // Emit an event that fees were claimed
        emit FeesClaimed(msg.sender, feeAmount0, feeAmount1);
    }

    // Batch token address claim
    function batchClaimFeesByTokenAddress(address[] calldata tokenAddresses) external nonReentrant {
        require(tokenAddresses.length > 0, "No token addresses provided");

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address tokenAddress = tokenAddresses[i];
            uint256 tokenId = tokenAddressToTokenId[tokenAddress];

            // Ensure tokenId exists for the given token address
            require(tokenId != 0, "Token address not associated with any tokenId");

            _claimFees(tokenId);
        }
    }

    // Function to claim fees based on token address (uses the tokenAddressToTokenId mapping)
    function claimFeesByTokenAddress(address tokenAddress) external nonReentrant{
        uint256 tokenId = tokenAddressToTokenId[tokenAddress];

        // Ensure tokenId exists for the given token address
        require(tokenId != 0, "Token address not associated with any tokenId");

        _claimFees(tokenId);
    }

    // Function to receive ERC721 tokens (to accept LP token deposits)
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Emit an event when an ERC721 token is received
        emit Received(from, tokenId);
        return this.onERC721Received.selector;
    }

    // Function to release the locked LP token back to the owner after the lock period ends
    function released(uint256 tokenId) external {
        TokenLockInfo memory lockInfo = tokenLocks[tokenId];

        // Ensure that the lock period has ended
        require(block.timestamp >= lockInfo.lockEndTime, "Lock period has not ended yet");

        // Ensure that the token has been initialized
        require(lockInfo.creator != address(0), "Token not initialized");

        // Get the owner's address (the contract owner)
        address owner = owner();

        // Transfer the locked LP token back to the owner
        IERC721 positionManager = IERC721(positionManagerAddress);
        positionManager.safeTransferFrom(address(this), owner, tokenId);

        // Clear the lock information
        delete tokenLocks[tokenId];
        delete tokenAddressToTokenId[lockInfo.token];

        // Emit an event when the token is released
        emit TokenReleased(tokenId, owner);
    }

    // Function to retrieve the lock information for a specific token
    function getTokenLockInfo(uint256 tokenId) external view returns (uint256 lockEndTime, address creator) {
        TokenLockInfo storage lockInfo = tokenLocks[tokenId];
        return (lockInfo.lockEndTime, lockInfo.creator);
    }

    // Function to retrieve a portion of the locked tokenIds (pagination)
    function getLockedTokenIds(uint256 start, uint256 count) external view returns (uint256[] memory) {
        require(start < tokenIds.length, "Start index out of bounds");

        // Calculate the number of items to return
        uint256 end = start + count;
        if (end > tokenIds.length) {
            end = tokenIds.length;
        }

        uint256[] memory paginatedTokenIds = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            paginatedTokenIds[i - start] = tokenIds[i];
        }

        return paginatedTokenIds;
    }

}
