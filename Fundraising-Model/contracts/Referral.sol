// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Referral is  ReentrancyGuard ,Ownable {

    // Mapping to store the referrer of each user
    mapping(address => address) public referrals;

    mapping(address => bool) public whitelist;

    event ReferralUpdated(address indexed user, address indexed referrer);

    constructor() {

    }

    function addToWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
    }

    function removeFromWhitelist(address _address) external onlyOwner {
        whitelist[_address] = false;
    }

    function setReferral(address user,address referrer) external {
        require(whitelist[msg.sender], "Caller is not in the whitelist");
        require(referrer != user, "You cannot refer yourself");
        if(referrals[user] != address(0)){
           return;
        }
        referrals[user] = referrer;
        emit ReferralUpdated(user, referrer);
    }

    // Function to query the referrer of a given user
    function getReferrer(address user) external view returns (address) {
        return referrals[user];
    }

    // Function to batch migrate users' referrers
    function migrateReferrers(address[] calldata users, address[] calldata newReferrers) external onlyOwner {
        require(users.length == newReferrers.length, "Users and referrers arrays must have the same length");
        for (uint256 i = 0; i < users.length; i++) {
            require(newReferrers[i] != users[i], "User cannot be their own referrer");
            referrals[users[i]] = newReferrers[i];
            emit ReferralUpdated(users[i], newReferrers[i]);
        }
    }
}
