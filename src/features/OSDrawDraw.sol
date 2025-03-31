// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OSDrawTickets.sol";
import "./OSDrawVRF.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";

/**
 * @title OSDrawDraw
 * @dev Handles the lottery drawing functionality
 */
contract OSDrawDraw is OSDrawTickets, OSDrawVRF {
    // Cooldown period before a draw where new ticket purchases are rejected
    uint256 private constant DRAW_COOLDOWN = 1 hours;
    
    /**
     * Trigger draw for previous day
     */
    function performDailyDraw() external {
        // Cache day calculations
        uint256 today = getCurrentDay();
        uint256 drawDay = today - 1;
        
        Storage storage s = _getStorage();
        if (s.drawExecuted[drawDay]) revert DrawAlreadyExecuted();
        
        // Verify there are tickets to draw from
        address[] memory participants = s.ticketsByDay[drawDay];
        uint256 participantCount = participants.length;
        if (participantCount == 0) revert NoTicketsForDraw();

        // Verify there's a pot to distribute
        uint256 pot = s.dailyPot[drawDay];
        if (pot == 0) revert InsufficientPot();

        // Mark draw as executed
        s.drawExecuted[drawDay] = true;
        
        // Cache entropy source to avoid multiple SLOADs
        address entropySource = s.entropySource;
        
        // Require VRF to be configured
        if (entropySource == address(0)) revert VRFNotConfigured();
            
        // Use VRF for true randomness
        requestRandomDraw(drawDay, msg.sender);
        // The actual draw will happen in the callback
    }
    
    // This modifies the buyTickets function to include anti-frontrunning protection
    function buyTickets(uint256 quantity) external payable override {
        // Get current time to check for cooldown period
        uint256 currentTime = block.timestamp;
        uint256 today = currentTime / 1 days;
        uint256 secondsIntoDay = currentTime % 1 days;
        
        // If close to end of day (within the cooldown period),
        // prevent new ticket purchases to avoid front-running
        if (secondsIntoDay > 1 days - DRAW_COOLDOWN) {
            revert("Ticket purchase not allowed during cooldown period");
        }
        
        // Normal ticket purchase logic
        uint256 price = getPrice(quantity);
        if (msg.value != price) revert IncorrectPaymentAmount();
        
        // Calculate current day
        Storage storage s = _getStorage();
        
        // Track tickets by day - first purchase adds to array
        if (s.userTicketCountByDay[today][msg.sender] == 0) {
            s.ticketsByDay[today].push(msg.sender);
        }
        
        // Update ticket count
        s.userTicketCountByDay[today][msg.sender] += quantity;
        
        // Add to daily pot
        s.dailyPot[today] += msg.value;
        
        emit TicketsPurchased(msg.sender, today, quantity, msg.value);
    }
    
    /**
     * Trigger draw for a specific pool
     * @param poolId The ID of the pool to draw for
     */
    function performPoolDraw(uint256 poolId) external {
        Storage storage s = _getStorage();
        
        // Verify pool exists and is active
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        
        // Ensure there's a balance to distribute
        if (pool.ethBalance == 0) revert InsufficientPot();
        
        // Cache entropy source
        address entropySource = s.entropySource;
        
        // Require VRF to be configured
        if (entropySource == address(0)) revert VRFNotConfigured();
        
        // Use VRF for true randomness
        requestRandomDraw(poolId, msg.sender);
        // The actual draw will happen in the callback
    }
} 