// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Ticket
 * @dev Structure to track user ticket information for the daily draw
 */
struct Ticket {
    // Number of tickets purchased by the user on a specific day
    uint256 purchased;
    
    // Number of tickets claimed by the user on a specific day
    uint256 claimed;
} 