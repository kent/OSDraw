// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";

contract OSDrawConfig is OSDrawStorage {
    // Share config
    uint256 private constant PROJECT_SHARE = 50;
    uint256 private constant PERCENT_DIVISOR = 100;

    // Ticket pricing (ETH)
    uint256 private constant PRICE_ONE = 0.01 ether;
    uint256 private constant PRICE_FIVE = 0.048 ether;
    uint256 private constant PRICE_TWENTY = 0.18 ether;
    uint256 private constant PRICE_HUNDRED = 0.80 ether;

    // --- Get price for allowed bundles only ---
    function getPrice(uint256 quantity) public pure returns (uint256) {
        if (quantity == 1) return PRICE_ONE;
        else if (quantity == 5) return PRICE_FIVE;
        else if (quantity == 20) return PRICE_TWENTY;
        else if (quantity == 100) return PRICE_HUNDRED;
        revert("Invalid ticket quantity");
    }
    
    // Public accessors for constants
    function getProjectShare() external pure returns (uint256) {
        return PROJECT_SHARE;
    }
    
    function getPercentDivisor() external pure returns (uint256) {
        return PERCENT_DIVISOR;
    }
    
    // Public accessor for admin share (from storage)
    function getAdminShare() external view returns (uint256) {
        return _getStorage().adminShare;
    }
    
    // --- Admin functions ---
    function updateOpenSourceRecipient(address newRecipient) external onlyManager {
        require(newRecipient != address(0), "Invalid recipient");
        _getStorage().openSourceRecipient = newRecipient;
        emit OpenSourceRecipientUpdated(newRecipient);
    }
    
    function transferManager(address newManager) external onlyManager {
        require(newManager != address(0), "Invalid manager");
        _getStorage().manager = newManager;
        emit ManagerTransferred(newManager);
    }
    
    // --- Modifiers ---
    modifier onlyManager() {
        require(msg.sender == _getStorage().manager, "Only manager can call this function");
        _;
    }
    
    // --- Events ---
    event OpenSourceRecipientUpdated(address newRecipient);
    event ManagerTransferred(address newManager);
} 