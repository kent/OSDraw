// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";
import "../interfaces/IVRF.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";

/**
 * @title OSDrawVRF
 * @dev Handles random number generation and callbacks for OSDraw
 */
contract OSDrawVRF is OSDrawStorage, IVRFSystemCallback {
    uint256 constant VRF_TRACE_ID = uint256(keccak256("app.osdraw.draw.v1"));
    
    /**
     * Set the entropy source address for VRF integration
     * @param entropySource Address of the VRF provider
     */
    function setEntropySource(address entropySource) external onlyAdmin {
        if (entropySource == address(0)) revert InvalidAddress();
        
        Storage storage s = _getStorage();
        s.entropySource = entropySource;
        
        emit EntropySourceUpdated(entropySource);
    }

    /**
     * Request a random number for the draw
     * @param poolId The ID of the pool for which to perform the draw
     * @param receiver The address that will receive the winnings
     */
    function requestRandomDraw(uint256 poolId, address receiver) internal returns (uint64) {
        Storage storage s = _getStorage();
        
        // Ensure entropy source is configured
        if (s.entropySource == address(0)) revert InvalidAddress();
        
        // Request random number
        IVRFSystem entropy = IVRFSystem(s.entropySource);
        uint64 seqNo = uint64(entropy.requestRandomNumberWithTraceId(VRF_TRACE_ID));
        
        // Store callback data
        s.callbackReceiver[seqNo] = receiver;
        s.callbackPool[seqNo] = poolId;
        
        return seqNo;
    }
    
    /**
     * Callback function for VRF provider
     * @param requestId The ID of the request
     * @param randomNumber The generated random number
     */
    function randomNumberCallback(uint256 requestId, uint256 randomNumber) external override {
        Storage storage s = _getStorage();
        
        // Validate caller is the entropy source
        if (msg.sender != s.entropySource) revert Unauthorized();
        
        uint64 seqNo = uint64(requestId);
        
        // Retrieve callback data
        address receiver = s.callbackReceiver[seqNo];
        uint256 poolId = s.callbackPool[seqNo];
        
        // Validate callback data exists
        if (receiver == address(0)) return; // Missing data, ignore callback
        
        // Clean up callback data
        s.callbackReceiver[seqNo] = address(0);
        s.callbackPool[seqNo] = 0;
        
        // Process the draw with the random number
        _processDraw(poolId, receiver, randomNumber);
    }
    
    /**
     * Process the draw with the provided randomness
     * @param poolId The ID of the pool
     * @param receiver The receiver address
     * @param randomNumber The random number for the draw
     */
    function _processDraw(uint256 poolId, address receiver, uint256 randomNumber) internal {
        Storage storage s = _getStorage();
        
        // Check if this is a day-based draw (legacy system) or a pool-based draw
        if (poolId < 10000) { // Assuming poolIds will never be this small, safer to use a flag
            _processDayDraw(poolId, randomNumber);
        } else {
            _processPoolDraw(poolId, randomNumber);
        }
    }
    
    /**
     * Process a day-based draw with the provided randomness
     * @param day The day to draw for
     * @param randomNumber The random number
     */
    function _processDayDraw(uint256 day, uint256 randomNumber) private {
        Storage storage s = _getStorage();
        
        // Use the random number to select a winner
        address[] memory participants = s.ticketsByDay[day];
        uint256 participantCount = participants.length;
        if (participantCount == 0) return;
        
        uint256 winnerIndex = randomNumber % participantCount;
        address winner = participants[winnerIndex];
        
        // Calculate prize distribution
        uint256 pot = s.dailyPot[day];
        if (pot == 0) return;
        
        s.dailyPot[day] = 0;
        
        uint256 adminAmount = (pot * s.adminShare) / 100;
        uint256 projectAmount = (pot * 50) / 100; // Project share is 50%
        uint256 winnerAmount = pot - adminAmount - projectAmount;
        
        // Distribute prizes
        payable(s.openSourceRecipient).transfer(projectAmount);
        payable(s.admin).transfer(adminAmount);
        payable(winner).transfer(winnerAmount);
        
        // Emit event
        emit DailyDrawPerformed(day, winner, winnerAmount);
    }
    
    /**
     * Process a pool-based draw with the provided randomness
     * @param poolId The pool ID to draw for
     * @param randomNumber The random number
     */
    function _processPoolDraw(uint256 poolId, uint256 randomNumber) private {
        // This will be implemented with full pool draw mechanics
        // Currently a placeholder
        revert("Pool draws not yet implemented");
    }
    
    /**
     * Access control: only admin can call functions with this modifier
     */
    modifier onlyAdmin() {
        if (msg.sender != _getStorage().admin) revert Unauthorized();
        _;
    }
} 