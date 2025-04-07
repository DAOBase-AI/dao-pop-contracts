// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {ERC20} from "./tokens/ERC20.sol";

contract Token is ERC20 {

    string public businessKey;

    uint256 public daoId;

    bool public sendingToPoolAllowed;

    address public poolAddress;

    uint256 public maxSupply;

    bool private initialized;

    address public factory;

    constructor() ERC20("", "") {}


    function initialize(
        string memory name,
        string memory symbol,
        string memory _businessKey,
        uint256 _daoId
    ) external  {
        require(!initialized, "Token: already initialized");
        initialized = true;
        factory = msg.sender;
        _initialize(name, symbol);
        businessKey = _businessKey;
        daoId = _daoId;
        maxSupply = 1100000000 * 1e18;
        _mint(msg.sender, maxSupply);
    }

    function enableSendingToPool() external  {
        require(msg.sender == factory,"not fct");
        sendingToPoolAllowed = true;
    }

    function setPool(address _poolAddress) external  {
        require(msg.sender == factory,"not fac");
        poolAddress = _poolAddress;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (!sendingToPoolAllowed && to == poolAddress) {
            revert("Transfers to the pool are not allowed before opening.");
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (!sendingToPoolAllowed && to == poolAddress) {
            revert("Transfers to the pool are not allowed before opening.");
        }
        return super.transferFrom(from, to, amount);
    }
}
