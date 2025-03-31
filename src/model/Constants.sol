// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants
 * @dev Centralized constants for the OSDraw system
 */
library Constants {
    // System constants
    uint256 internal constant PERCENT_DIVISOR = 100;
    uint256 internal constant PROJECT_SHARE = 50;
    uint256 internal constant POOL_ID_THRESHOLD = 10000; // Threshold to distinguish pool vs day IDs
    
    // VRF constants
    uint256 internal constant VRF_TRACE_ID = uint256(keccak256("game.osdraw.vrf.v1"));
    
    // Timellock constants
    uint256 internal constant DEFAULT_TIMELOCK_DELAY = 2 days;
    uint256 internal constant MIN_TIMELOCK_DELAY = 1 days;
    uint256 internal constant MAX_TIMELOCK_DELAY = 30 days;
    
    // Reentrancy guard constants
    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    
    // Storage slot for diamond storage pattern
    bytes32 internal constant STORAGE_SLOT = keccak256("app.osdraw.storage.v1");
    
    // Ticket pricing (ETH)
    uint256 internal constant PRICE_ONE = 0.01 ether;
    uint256 internal constant PRICE_FIVE = 0.048 ether;
    uint256 internal constant PRICE_TWENTY = 0.18 ether;
    uint256 internal constant PRICE_HUNDRED = 0.80 ether;
} 