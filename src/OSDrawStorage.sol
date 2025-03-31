// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./model/Ticket.sol";
import "./model/Pool.sol";
import "./model/Config.sol";
import "./model/Constants.sol";
import "./interfaces/IVRF.sol";

/**
 * @title OSDrawStorage
 * @dev Centralized storage contract for OSDraw system
 */
contract OSDrawStorage {
    // Storage structure to keep all state variables organized
    struct Storage {
        // Roles
        address admin;
        address manager;
        address openSourceRecipient;
        
        // Configuration
        uint256 adminShare;
        
        // Reentrancy guard
        uint256 reentrancyStatus;
        
        // Timelock functionality
        mapping(bytes32 => uint256) timelockOperations;
        uint256 timelockDelay;
        
        // State - current implementation
        mapping(uint256 => address[]) ticketsByDay;
        mapping(uint256 => mapping(address => uint256)) userTicketCountByDay;
        mapping(uint256 => bool) drawExecuted;
        mapping(uint256 => uint256) dailyPot;
        
        // Future implementation with pools and tickets
        mapping(uint256 => Pool) pools;             // poolId => Pool
        mapping(uint256 => mapping(address => Ticket)) tickets; // poolId => userAddress => Ticket
        
        // Add tracking of pool participants
        mapping(uint256 => address[]) poolParticipants; // poolId => array of participant addresses
        mapping(uint256 => uint256) totalPoolTickets;   // poolId => total tickets sold (for random selection)
        
        // VRF integration
        address entropySource;                      // VRF provider contract
        mapping(uint64 => address) callbackReceiver; // seqNo => user address
        mapping(uint64 => uint256) callbackPool;     // seqNo => poolId
        
        // System parameters
        Config config;
    }
    
    // Use constants from Constants library
    uint256 internal constant NOT_ENTERED = Constants.NOT_ENTERED;
    uint256 internal constant ENTERED = Constants.ENTERED;
    
    // Use a specific storage slot to prevent collisions during upgrades
    bytes32 private constant STORAGE_SLOT = Constants.STORAGE_SLOT;
    
    // Internal function to access storage
    function _getStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
    
    /**
     * @dev Prevents a contract function from being reentered.
     * Should be used to prevent reentrancy attacks across the entire system.
     */
    modifier nonReentrantShared() {
        Storage storage s = _getStorage();
        // On the first call to nonReentrant, reentrancyStatus will be NOT_ENTERED
        require(s.reentrancyStatus != ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        s.reentrancyStatus = ENTERED;

        _;

        // By storing the original value once again, a refund is triggered
        s.reentrancyStatus = NOT_ENTERED;
    }
} 