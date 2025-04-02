// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";
import "../model/Constants.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";

contract OSDrawConfig is OSDrawStorage {
    // Use constants from Constants library
    uint256 private constant PROJECT_SHARE = Constants.PROJECT_SHARE;
    uint256 private constant PERCENT_DIVISOR = Constants.PERCENT_DIVISOR;

    // Ticket pricing from Constants library
    uint256 private constant PRICE_ONE = Constants.PRICE_ONE;
    uint256 private constant PRICE_FIVE = Constants.PRICE_FIVE;
    uint256 private constant PRICE_TWENTY = Constants.PRICE_TWENTY;
    uint256 private constant PRICE_HUNDRED = Constants.PRICE_HUNDRED;

    // --- Get price for allowed bundles only ---
    function getPrice(uint256 quantity) public pure virtual returns (uint256) {
        if (quantity == 1) return PRICE_ONE;
        else if (quantity == 5) return PRICE_FIVE;
        else if (quantity == 20) return PRICE_TWENTY;
        else if (quantity == 100) return PRICE_HUNDRED;
        revert InvalidTicketQuantity();
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
        if (newRecipient == address(0)) revert InvalidAddress();
        _getStorage().openSourceRecipient = newRecipient;
        emit OpenSourceRecipientUpdated(newRecipient);
    }
    
    function transferManager(address newManager) external onlyManager {
        if (newManager == address(0)) revert InvalidAddress();
        _getStorage().manager = newManager;
        emit ManagerTransferred(newManager);
    }
    
    // --- Modifiers ---
    modifier onlyManager() {
        if (msg.sender != _getStorage().manager) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Emergency withdraw function
     * Note: Timelock protection is now handled by the separate TimelockController contract
     * 
     * @param amount The amount of ETH to withdraw
     * @param recipient The address to send funds to
     */
    function emergencyWithdraw(uint256 amount, address recipient) external {
        Storage storage s = _getStorage();
        if (msg.sender != s.config.owner) revert Unauthorized();
        
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0 || amount > address(this).balance) revert InvalidAmount();
        
        // Emit event for transparency
        emit EmergencyWithdrawal(msg.sender, recipient, amount);
        
        // Use safe transfer pattern
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
    }
} 