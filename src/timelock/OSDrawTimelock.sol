// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title OSDrawTimelock
 * @dev TimelockController for OSDraw governance operations
 * 
 * This contract is used to introduce a delay between a proposal and its execution.
 * It serves as a replacement for the homegrown timelock implementation with
 * a standardized, audited implementation from OpenZeppelin.
 */
contract OSDrawTimelock is TimelockController {
    /**
     * @dev Constructor for the timelock controller
     * 
     * @param minDelay Minimum delay before operations can be executed (in seconds)
     * @param proposers List of addresses that can propose operations
     * @param executors List of addresses that can execute operations
     * @param admin Optional admin address (can be address(0) to rely on self-administration)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
} 