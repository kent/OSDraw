// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Config
 * @dev Structure to hold global configuration parameters
 */
struct Config {
    // Share percentages
    uint256 adminShare;
    uint256 projectShare;
    
    // Fees in basis points
    uint16 feeBPS;
    
    // Current supply and pool tracking
    uint256 currentSupply;
    uint256 currentPoolId;
    
    // System addresses
    address owner;
    address entropySource; // For future VRF integration
} 