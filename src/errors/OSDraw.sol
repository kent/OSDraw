// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Custom errors for the OSDraw system
 */

// Authorization errors
error Unauthorized();
error InvalidAddress();

// Input validation errors
error InvalidTicketQuantity();
error IncorrectPaymentAmount();
error InvalidAmount();
error InvalidPoolParameters();

// Draw execution errors
error DrawAlreadyExecuted();
error NoTicketsForDraw();
error InsufficientPot();

// Ticket errors
error InsufficientTicketBalance();

// Pool errors
error PoolNotFound();
error PoolNotActive();

// System errors
error TransferFailed();

// Timelock errors
error OperationNotQueued();
error OperationNotReady();
error VRFNotConfigured(); 