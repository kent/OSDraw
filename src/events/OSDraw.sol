// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Events for the OSDraw system
 */

// Ticket events
event TicketsPurchased(address indexed buyer, uint256 indexed day, uint256 quantity, uint256 amountPaid);
event PoolTicketsPurchased(uint256 indexed poolId, address indexed buyer, uint256 quantity, uint256 amountPaid);

// Draw events
event DailyDrawPerformed(uint256 indexed day, address indexed winner, uint256 amountWon);
event PoolDrawPerformed(uint256 indexed poolId, address indexed winner, uint256 amountWon);

// Admin events
event OpenSourceRecipientUpdated(address indexed newRecipient);
event ManagerTransferred(address indexed newManager);
event EntropySourceUpdated(address indexed newEntropySource);

// Pool management events
event PoolCreated(uint256 indexed poolId, uint256 ticketPrice, bool active);
event PoolUpdated(uint256 indexed poolId, uint256 ticketPrice, bool active);
event PoolStatusChanged(uint256 indexed poolId, bool active);
event LiquidityAdded(uint256 indexed poolId, uint256 amount);
event LiquidityWithdrawn(uint256 indexed poolId, uint256 amount);

// Payment events
event PaymentWithdrawn(address indexed user, uint256 amount);

// Emergency events
event EmergencyWithdrawal(address indexed sender, address indexed recipient, uint256 amount);
event EmergencyWithdrawalQueued(address indexed sender, address indexed recipient, uint256 amount);

// Timelock events
event TimelockDelayUpdated(uint256 newDelay);
event OperationQueued(bytes32 indexed operationId, uint256 executeTime);
event OperationExecuted(bytes32 indexed operationId); 