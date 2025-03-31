// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Pool
 * @dev Structure to define a prize pool configuration
 */
struct Pool {
    // Price per ticket in ETH
    uint256 ticketPrice;
    
    // Total number of tickets sold for this pool
    uint256 totalSold;
    
    // Total number of tickets redeemed from this pool
    uint256 totalRedeemed;
    
    // Current ETH balance in the pool
    uint256 ethBalance;
    
    // Whether this pool is active (packed with other small variables)
    bool active;
} 