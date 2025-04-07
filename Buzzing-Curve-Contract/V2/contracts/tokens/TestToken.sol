// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestToken is IERC20, ERC20Permit {
    address public minter;
    error NotMinter();

    constructor(string memory name,string memory symbol) ERC20(name,symbol) ERC20Permit(symbol) {
        minter = msg.sender;
        _mint(msg.sender,100000000 ether);
    }

    function setMinter(address _minter) external {
        if (msg.sender != minter) revert NotMinter();
        minter = _minter;
    }

    function mint(address account, uint256 amount) external returns (bool) {
        if (msg.sender != minter ) revert NotMinter();
        _mint(account, amount);
        return true;
    }

}
