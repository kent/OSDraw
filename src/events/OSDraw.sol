// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Events for the OSDraw system
 */

// Ticket events
event TicketsPurchased(address indexed buyer, uint256 day, uint256 quantity, uint256 amountPaid);
event PoolTicketsPurchased(uint256 indexed poolId, address indexed buyer, uint256 quantity, uint256 amountPaid);

// Draw events
event DailyDrawPerformed(uint256 day, address winner, uint256 amountWon);

// Admin events
event OpenSourceRecipientUpdated(address newRecipient);
event ManagerTransferred(address newManager);
event EntropySourceUpdated(address newEntropySource);

// Pool management events
event PoolCreated(uint256 indexed poolId, uint256 ticketPrice, bool active);
event PoolUpdated(uint256 indexed poolId, uint256 ticketPrice, bool active);
event PoolStatusChanged(uint256 indexed poolId, bool active);
event LiquidityAdded(uint256 indexed poolId, uint256 amount);
event LiquidityWithdrawn(uint256 indexed poolId, uint256 amount); 