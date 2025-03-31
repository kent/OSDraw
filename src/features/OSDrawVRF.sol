// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";
import "../interfaces/IVRF.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";
import "../model/Constants.sol";

/**
 * @title OSDrawVRF
 * @dev Handles random number generation and callbacks for OSDraw
 */
contract OSDrawVRF is OSDrawStorage, IVRFSystemCallback {
    // Constants from Constants library
    uint256 constant VRF_TRACE_ID = Constants.VRF_TRACE_ID;
    uint256 private constant PERCENT_DIVISOR = Constants.PERCENT_DIVISOR;
    uint256 private constant PROJECT_SHARE = Constants.PROJECT_SHARE;
    uint256 private constant POOL_ID_THRESHOLD = Constants.POOL_ID_THRESHOLD;
    
    // Add a new mapping for pending payments
    mapping(address => uint256) private _pendingPayments;
    
    /**
     * Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() virtual {
        Storage storage s = _getStorage();
        require(s.reentrancyStatus != ENTERED, "ReentrancyGuard: reentrant call");
        s.reentrancyStatus = ENTERED;
        _;
        s.reentrancyStatus = NOT_ENTERED;
    }
    
    /**
     * Set the entropy source address for VRF integration
     * @param entropySource Address of the VRF provider
     */
    function setEntropySource(address entropySource) external onlyAdmin {
        if (entropySource == address(0)) revert InvalidAddress();
        
        Storage storage s = _getStorage();
        s.entropySource = entropySource;
        
        emit EntropySourceUpdated(entropySource);
    }

    /**
     * Request a random number for the draw
     * @param poolId The ID of the pool for which to perform the draw
     * @param receiver The address that will receive the winnings
     */
    function requestRandomDraw(uint256 poolId, address receiver) internal returns (uint64) {
        Storage storage s = _getStorage();
        
        // Ensure entropy source is configured
        if (s.entropySource == address(0)) revert InvalidAddress();
        
        // Request random number
        IVRFSystem entropy = IVRFSystem(s.entropySource);
        uint64 seqNo = uint64(entropy.requestRandomNumberWithTraceId(VRF_TRACE_ID));
        
        // Store callback data
        s.callbackReceiver[seqNo] = receiver;
        s.callbackPool[seqNo] = poolId;
        
        return seqNo;
    }
    
    /**
     * Callback function for VRF provider
     * @param requestId The ID of the request
     * @param randomNumber The generated random number
     */
    function randomNumberCallback(uint256 requestId, uint256 randomNumber) external override nonReentrant {
        Storage storage s = _getStorage();
        
        // Validate caller is the entropy source
        if (msg.sender != s.entropySource) revert Unauthorized();
        
        uint64 seqNo = uint64(requestId);
        
        // Retrieve callback data
        address receiver = s.callbackReceiver[seqNo];
        if (receiver == address(0)) revert("Invalid request ID");
        
        uint256 poolId = s.callbackPool[seqNo];
        
        // Clean up callback data
        s.callbackReceiver[seqNo] = address(0);
        s.callbackPool[seqNo] = 0;
        
        // Process the draw based on pool ID
        if (poolId < POOL_ID_THRESHOLD) {
            _processDayDraw(poolId, randomNumber);
        } else {
            _processPoolDraw(poolId, receiver, randomNumber);
        }
    }
    
    /**
     * Process a day-based draw with the provided randomness
     * @param day The day to draw for
     * @param randomNumber The random number
     */
    function _processDayDraw(uint256 day, uint256 randomNumber) private {
        Storage storage s = _getStorage();
        
        // Use the random number to select a winner
        address[] memory participants = s.ticketsByDay[day];
        uint256 participantCount = participants.length;
        if (participantCount == 0) return;
        
        // Select winner with random number
        uint256 winnerIndex = randomNumber % participantCount;
        address winner = participants[winnerIndex];
        
        // Calculate prize distribution
        uint256 pot = s.dailyPot[day];
        if (pot == 0) return;
        
        s.dailyPot[day] = 0;
        
        uint256 adminAmount = (pot * s.adminShare) / PERCENT_DIVISOR;
        uint256 projectAmount = (pot * PROJECT_SHARE) / PERCENT_DIVISOR;
        uint256 winnerAmount = pot - adminAmount - projectAmount;
        
        // Validate recipients
        address osRecipient = s.openSourceRecipient;
        address adminRecipient = s.admin;
        
        if (osRecipient == address(0) || adminRecipient == address(0) || winner == address(0)) {
            revert InvalidAddress();
        }
        
        // Use pull pattern - store pending amounts
        _addPendingPayment(osRecipient, projectAmount);
        _addPendingPayment(adminRecipient, adminAmount);
        _addPendingPayment(winner, winnerAmount);
        
        // Emit event
        emit DailyDrawPerformed(day, winner, winnerAmount);
    }
    
    /**
     * Process a pool-based draw with the provided randomness
     * @param poolId The pool ID to draw for
     * @param randomNumber The random number
     */
    function _processPoolDraw(uint256 poolId, address /* receiver */, uint256 randomNumber) private {
        Storage storage s = _getStorage();
        
        // Get pool data
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) return; // Pool not found
        if (pool.ethBalance == 0) return; // No funds to distribute
        
        // Get the participants and select a winner based on tickets bought
        address[] memory participants = s.poolParticipants[poolId];
        uint256 participantCount = participants.length;
        
        // If no participants, just return
        if (participantCount == 0) return;
        
        uint256 winnerIndex = randomNumber % participantCount;
        address winner = participants[winnerIndex];
        
        // Calculate prize distribution
        uint256 pot = pool.ethBalance;
        pool.ethBalance = 0;
        
        uint256 adminAmount = (pot * s.adminShare) / PERCENT_DIVISOR;
        uint256 projectAmount = (pot * PROJECT_SHARE) / PERCENT_DIVISOR;
        uint256 winnerAmount = pot - adminAmount - projectAmount;
        
        // Use pull pattern instead of direct transfers
        _addPendingPayment(s.openSourceRecipient, projectAmount);
        _addPendingPayment(s.admin, adminAmount);
        _addPendingPayment(winner, winnerAmount);
        
        // Increase redeemed count
        pool.totalRedeemed++;
        
        // Emit event for the winner
        emit PoolDrawPerformed(poolId, winner, winnerAmount);
    }
    
    /**
     * Add to the pending payment for an address
     * @param recipient The recipient
     * @param amount The amount to add
     */
    function _addPendingPayment(address recipient, uint256 amount) private {
        if (recipient == address(0) || amount == 0) return;
        _pendingPayments[recipient] += amount;
    }
    
    /**
     * Get the pending payment for an address
     * @param recipient The recipient
     * @return The pending payment amount
     */
    function getPendingPayment(address recipient) external view returns (uint256) {
        return _pendingPayments[recipient];
    }
    
    /**
     * Withdraw pending payment
     */
    function withdrawPendingPayment() external nonReentrant {
        uint256 amount = _pendingPayments[msg.sender];
        if (amount == 0) revert InvalidAmount();
        
        // Clear pending payment before transfer to prevent reentrancy
        _pendingPayments[msg.sender] = 0;
        
        // Transfer ETH to the recipient using the safer call pattern
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        
        // Revert if transfer fails to ensure consistent state
        if (!success) revert TransferFailed();
        
        emit PaymentWithdrawn(msg.sender, amount);
    }
    
    /**
     * Access control: only admin can call functions with this modifier
     */
    modifier onlyAdmin() virtual {
        if (msg.sender != _getStorage().admin) revert Unauthorized();
        _;
    }
} 