// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OSDrawConfig.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";

contract OSDrawTickets is OSDrawConfig {
    /**
     * Buy preset quantity of entries
     * @param quantity The number of tickets to purchase
     */
    function buyTickets(uint256 quantity) external payable {
        uint256 price = getPrice(quantity);
        if (msg.value != price) revert IncorrectPaymentAmount();

        uint256 day = getCurrentDay();
        Storage storage s = _getStorage();
        
        for (uint256 i = 0; i < quantity; i++) {
            s.ticketsByDay[day].push(msg.sender);
        }
        
        // Update user ticket count for O(1) lookup
        s.userTicketCountByDay[day][msg.sender] += quantity;

        s.dailyPot[day] += msg.value;
        emit TicketsPurchased(msg.sender, day, quantity, msg.value);
    }
    
    /**
     * Buy tickets for a specific pool
     * @param poolId The pool ID to buy tickets for
     * @param quantity The number of tickets to purchase
     */
    function buyPoolTickets(uint256 poolId, uint256 quantity) external payable {
        Storage storage s = _getStorage();
        
        // Validate pool exists and is active
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        
        // Calculate and verify price
        uint256 price = pool.ticketPrice * quantity;
        if (msg.value != price) revert IncorrectPaymentAmount();
        
        // Update pool state
        pool.totalSold += quantity;
        pool.ethBalance += msg.value;
        
        // Update user tickets
        s.tickets[poolId][msg.sender].purchased += quantity;
        s.config.currentSupply += quantity;
        
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