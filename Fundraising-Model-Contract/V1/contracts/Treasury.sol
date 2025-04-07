// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Treasury is ReentrancyGuard{
    address public owner;
    address public token;
    bool public initialized;

    uint256 public dailyWithdrawCount;
    uint256 public totalWithdrawCount;
    uint256 public lastWithdrawTime;


    event ETHWithdrawn(address indexed recipient, uint256 amount,uint256 blockTime);
    event ERC20Withdrawn(address indexed token, address indexed recipient, uint256 amount,uint256 blockTime);
    event NFTWithdrawn(address indexed nft, address indexed recipient, uint256 tokenId,uint256 blockTime);
    event Executed(address indexed target, uint256 value, bytes data, bytes response,uint256 blockTime);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner,uint256 blockTime);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {}

    function initialize(address _owner,address _token) external {
        require(!initialized, "Treasury: already initialized");
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
        token = _token;
        initialized = true;
    }

    function withdrawETH(uint256 amount, address recipient) external onlyOwner nonReentrant{
        require(recipient != address(0), "Invalid recipient address");
        require(address(this).balance >= amount, "Insufficient balance");

        _validateWithdraw(amount);

        payable(recipient).transfer(amount);
        emit ETHWithdrawn(recipient, amount,block.timestamp);
    }

    function withdrawERC20(address _token, uint256 _amount, address _recipient) external onlyOwner nonReentrant {
        require(_token != address(0), "Invalid token address");
        require(_recipient != address(0), "Invalid recipient address");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance >= _amount, "Insufficient token balance");

        require(IERC20(_token).transfer(_recipient, _amount), "Token transfer failed");

        emit ERC20Withdrawn(_token, _recipient, _amount,block.timestamp);

    }

    function withdrawNFT(address _nft, uint256 _tokenId, address _recipient) external onlyOwner nonReentrant {
        require(_nft != address(0), "Invalid NFT address");
        require(_recipient != address(0), "Invalid recipient address");

        IERC721(_nft).safeTransferFrom(address(this), _recipient, _tokenId);
        emit NFTWithdrawn(_nft, _recipient, _tokenId,block.timestamp);
    }

    function execute(address target, uint256 value, bytes calldata data) external onlyOwner nonReentrant returns (bytes memory) {
        require(target != address(0), "Invalid target address");

        (bool success, bytes memory response) = target.call{value: value}(data);
        require(success, "Execution failed");

        emit Executed(target, value, data, response,block.timestamp);
        return response;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        require(newOwner != owner, "Already the owner");

        address oldOwner = owner;
        owner = newOwner;

        emit OwnershipTransferred(oldOwner, newOwner,block.timestamp);
    }

    function _validateWithdraw(uint256 amount) internal {
        if(totalWithdrawCount >= 5){
            return;
        }

        // Check if it's the same day
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastDay = lastWithdrawTime / 1 days;

        if (currentDay > lastDay ) {
            dailyWithdrawCount = 0;  // Reset the daily withdrawal count at the start of a new day
        }
        require(dailyWithdrawCount == 0, "Already withdrawn today");
        uint256 maxAllowed = address(this).balance / 2; // Calculate half of the balance
        require(amount <= maxAllowed, "Exceeds maximum withdrawal limit for today");
        dailyWithdrawCount++;
        totalWithdrawCount++;
        lastWithdrawTime = block.timestamp;
    }

    function getDayWithdrawBalance() external view returns (uint256) {
        uint256 _balance =address(this).balance;
        if(totalWithdrawCount >= 5){
            return _balance;
        }
        // Check if it's the same day
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastDay = lastWithdrawTime / 1 days;
        if (lastDay >= currentDay ) {
            return 0;
        }
         return _balance/2;
    }

    function getERC20Balance(address _token) external view returns (uint256) {
        require(_token != address(0), "Invalid token address");
        return IERC20(_token).balanceOf(address(this));
    }

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
