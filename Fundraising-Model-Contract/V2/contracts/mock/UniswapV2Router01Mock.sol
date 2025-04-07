// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./UniswapV2FactoryMock.sol";
import "./IWETH.sol";

contract UniswapV2Router01Mock {

    address public immutable weth;
    address public factory;
    address public owner;

    event LiquidityAdded(
        address indexed pair,
        address indexed user,
        uint amountTokenA,
        uint amountTokenB,
        uint liquidity
    );

    constructor(address _factory, address _weth) {
        factory = _factory; // Mock Factory address
        weth = _weth; // Mock WETH address
        owner = msg.sender; // Set deployer as the owner
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "UniswapV2Router01Mock: NOT_OWNER");
        _;
    }

    function WETH() external view returns (address) {
        return weth;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
    external
    payable
    returns (uint amountToken, uint amountETH, uint liquidity)
    {
        require(block.timestamp <= deadline, "UniswapV2Router01Mock: EXPIRED");
        require(msg.value >= amountETHMin, "UniswapV2Router01Mock: INSUFFICIENT_ETH");

        // Ensure Pair exists
        address pair = UniswapV2FactoryMock(factory).getPair(token, weth);
        if (pair == address(0)) {
            pair = UniswapV2FactoryMock(factory).createPair(token, weth);
        }

        MockPair mockPair = MockPair(pair);

        // Transfer tokens from the user to the pair
        IERC20 tokenContract = IERC20(token);

        amountETH = msg.value;
        liquidity = amountToken + amountETH;
        mockPair.mint(to,liquidity);

        // Send ETH to the pair
        tokenContract.transferFrom(msg.sender, pair, amountTokenDesired);
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).transfer(pair, amountETH);

        // Mint liquidity
        amountToken = tokenContract.balanceOf(pair);
        require(amountToken >= amountTokenMin, "UniswapV2Router01Mock: INSUFFICIENT_TOKEN");
        require(amountETH >= amountETHMin, "UniswapV2Router01Mock: INSUFFICIENT_ETH");

        emit LiquidityAdded(pair, to, amountToken, amountETH, liquidity);
    }

    function withdrawTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(amount <= balance, "UniswapV2Router01Mock: INSUFFICIENT_BALANCE");
        tokenContract.transfer(to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        uint256 balance = address(this).balance;
        require(amount <= balance, "UniswapV2Router01Mock: INSUFFICIENT_BALANCE");
        to.transfer(amount);
    }

    receive() external payable {}
}
