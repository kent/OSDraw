// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";
import "../model/Constants.sol";

/**
 * @title OSDrawTickets
 * @dev Handles ticket purchasing and tracking
 */
contract OSDrawTickets is OSDrawStorage {
    /**
     * Buy tickets for the current day
     * @param quantity Number of tickets to buy (must be a valid quantity)
     */
    function buyTickets(uint256 quantity) external payable virtual {
        uint256 price = getPrice(quantity);
        if (msg.value != price) revert IncorrectPaymentAmount();
        
        // Calculate current day
        uint256 today = getCurrentDay();
        
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
     * Get the price for a specific ticket quantity
     * @param quantity The number of tickets
     * @return The price in ETH
     */
    function getPrice(uint256 quantity) public pure virtual returns (uint256) {
        if (quantity == 1) return Constants.PRICE_ONE;
        else if (quantity == 5) return Constants.PRICE_FIVE;
        else if (quantity == 20) return Constants.PRICE_TWENTY;
        else if (quantity == 100) return Constants.PRICE_HUNDRED;
        revert InvalidTicketQuantity();
    }
    
    /**
     * Buy tickets for a specific prize pool
     * @param poolId The ID of the pool
     * @param quantity Number of tickets to buy
     */
    function buyPoolTickets(uint256 poolId, uint256 quantity) external payable {
        Storage storage s = _getStorage();
        
        // Validate pool ID
        if (poolId == 0 || poolId < Constants.POOL_ID_THRESHOLD) revert PoolNotFound();
        
        // Get pool
        Pool storage pool = s.pools[poolId];
        
        // Verify pool is valid and active
        if (pool.ticketPrice == 0) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        
        // Strict quantity validation to prevent overflow attacks
        if (quantity == 0 || quantity > 1000) revert InvalidTicketQuantity();
        
        // Protect against multiplication overflow in price calculation
        // For extremely high ticket prices, this would still allow up to 1000 tickets
        // without risking overflow
        uint256 expectedPayment;
        unchecked {
            // Even with unchecked, we've validated the quantity is <= 1000
            // so overflow is impossible for any realistic ticket price
            expectedPayment = pool.ticketPrice * quantity;
        }
        
        // Additional check: if price is too high, operations might overflow
        if (pool.ticketPrice > 0 && expectedPayment / pool.ticketPrice != quantity) 
            revert InvalidTicketQuantity();
        
        // Verify payment amount exactly matches the expected amount
        if (msg.value != expectedPayment) revert IncorrectPaymentAmount();
        
        // Add to pool balance
        pool.ethBalance += msg.value;
        pool.totalSold += quantity;
        
        // Update user ticket tracking
        Ticket storage userTicket = s.tickets[poolId][msg.sender];
        
        // Track first-time buyers in this pool (similar to daily tickets)
        if (userTicket.purchased == 0) {
            s.poolParticipants[poolId].push(msg.sender);
        }
        
        // Protect against overflow
        if (userTicket.purchased + quantity < userTicket.purchased) revert InvalidTicketQuantity();
        if (s.config.currentSupply + quantity < s.config.currentSupply) revert InvalidTicketQuantity();
        
        userTicket.purchased += quantity;
        s.config.currentSupply += quantity;
        
        // Update total pool tickets for random selection
        s.totalPoolTickets[poolId] += quantity;
        
        emit PoolTicketsPurchased(poolId, msg.sender, quantity, msg.value);
    }
    
    /**
     * Get tickets for a specific day (for tests)
     * @param day The day to get tickets for
     * @return Array of addresses that purchased tickets
     */
    function getTicketsByDay(uint256 day) external view returns (address[] memory) {
        return _getStorage().ticketsByDay[day];
    }

    /**
     * Get ticket count for a specific user and day
     * @param user The user address
     * @param day The day to check
     * @return Number of tickets purchased
     */
    function getUserTicketCount(address user, uint256 day) external view returns (uint256) {
        // O(1) lookup instead of O(n) loop
        return _getStorage().userTicketCountByDay[day][user];
    }
    
    /**
     * Get ticket information for a user in a specific pool
     * @param poolId The pool ID
     * @param user The user address
     * @return Ticket struct with purchase info
     */
    function getUserPoolTickets(uint256 poolId, address user) external view returns (Ticket memory) {
        return _getStorage().tickets[poolId][user];
    }

    /**
     * Utility: Day ID from timestamp (UTC)
     * @return Current day ID
     */
    function getCurrentDay() public view returns (uint256) {
        // Use unchecked for division (safe operation)
        unchecked {
            return block.timestamp / 1 days;
        }
    }
} 