// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./model/Ticket.sol";
import "./model/Pool.sol";
import "./model/Config.sol";
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
        
        // State - current implementation
        mapping(uint256 => address[]) ticketsByDay;
        mapping(uint256 => mapping(address => uint256)) userTicketCountByDay;
        mapping(uint256 => bool) drawExecuted;
        mapping(uint256 => uint256) dailyPot;
        
        // Future implementation with pools and tickets
        mapping(uint256 => Pool) pools;             // poolId => Pool
        mapping(uint256 => mapping(address => Ticket)) tickets; // poolId => userAddress => Ticket
        
        // VRF integration
        address entropySource;                      // VRF provider contract
        mapping(uint64 => address) callbackReceiver; // seqNo => user address
        mapping(uint64 => uint256) callbackPool;     // seqNo => poolId
        
        // System parameters
        Config config;
    }
    
    // Use a specific storage slot to prevent collisions during upgrades
    bytes32 private constant STORAGE_SLOT = keccak256("app.osdraw.storage.v1");
    
    // Internal function to access storage
    function _getStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
} 