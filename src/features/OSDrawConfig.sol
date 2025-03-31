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
     * @dev Set the timelock delay (time required between queuing and execution)
     * @param newDelay The new delay in seconds
     */
    function setTimelockDelay(uint256 newDelay) external {
        Storage storage s = _getStorage();
        if (msg.sender != s.config.owner) revert Unauthorized();
        
        if (newDelay < Constants.MIN_TIMELOCK_DELAY || newDelay > Constants.MAX_TIMELOCK_DELAY) {
            revert InvalidAmount();
        }
        
        s.timelockDelay = newDelay;
        
        emit TimelockDelayUpdated(newDelay);
    }

    /**
     * @dev Queue a timelock operation
     * @param operationId Unique identifier for the operation
     * @return The timestamp when the operation will be executable
     */
    function queueTimelockOperation(bytes32 operationId) internal returns (uint256) {
        Storage storage s = _getStorage();
        
        if (s.timelockDelay == 0) {
            // If timelock not initialized, set a default
            s.timelockDelay = Constants.DEFAULT_TIMELOCK_DELAY;
        }
        
        uint256 executeTime = block.timestamp + s.timelockDelay;
        s.timelockOperations[operationId] = executeTime;
        
        emit OperationQueued(operationId, executeTime);
        return executeTime;
    }

    /**
     * @dev Checks if a timelock operation is ready to execute
     * @param operationId Unique identifier for the operation
     * @return If the operation is executable
     */
    function isOperationReady(bytes32 operationId) internal view returns (bool) {
        Storage storage s = _getStorage();
        uint256 queuedTime = s.timelockOperations[operationId];
        
        return queuedTime > 0 && block.timestamp >= queuedTime;
    }

    /**
     * @dev Consumes a timelock operation, marking it as executed
     * @param operationId Unique identifier for the operation
     */
    function executeOperation(bytes32 operationId) internal {
        Storage storage s = _getStorage();
        if (s.timelockOperations[operationId] == 0) revert OperationNotQueued();
        if (block.timestamp < s.timelockOperations[operationId]) revert OperationNotReady();
        
        // Remove operation from queue after execution
        delete s.timelockOperations[operationId];
        
        emit OperationExecuted(operationId);
    }

    /**
     * @dev Emergency withdraw with timelock protection
     * @param amount The amount of ETH to withdraw
     * @param recipient The address to send funds to
     */
    function emergencyWithdraw(uint256 amount, address recipient) external {
        Storage storage s = _getStorage();
        if (msg.sender != s.config.owner) revert Unauthorized();
        
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0 || amount > address(this).balance) revert InvalidAmount();
        
        // Create a unique operation ID based on the parameters
        bytes32 operationId = keccak256(abi.encode(
            "emergencyWithdraw",
            amount,
            recipient,
            block.chainid
        ));
        
        // Check if operation is already queued and ready
        if (!isOperationReady(operationId)) {
            // Queue the operation if not ready
            queueTimelockOperation(operationId);
            emit EmergencyWithdrawalQueued(msg.sender, recipient, amount);
            return;
        }
        
        // Execute operation
        executeOperation(operationId);
        
        // Emit event for transparency
        emit EmergencyWithdrawal(msg.sender, recipient, amount);
        
        // Use safe transfer pattern
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
    }
} 