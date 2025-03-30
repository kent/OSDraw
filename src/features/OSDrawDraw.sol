// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OSDrawTickets.sol";
import "../OSDrawVRF.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";

/**
 * @title OSDrawDraw
 * @dev Handles the lottery drawing functionality
 */
contract OSDrawDraw is OSDrawTickets, OSDrawVRF {
    /**
     * Trigger draw for previous day
     */
    function performDailyDraw() external {
        // Cache day calculations
        uint256 today = getCurrentDay();
        uint256 drawDay = today - 1;
        
        Storage storage s = _getStorage();
        if (s.drawExecuted[drawDay]) revert DrawAlreadyExecuted();
        
        // Verify there are tickets to draw from
        address[] memory participants = s.ticketsByDay[drawDay];
        uint256 participantCount = participants.length;
        if (participantCount == 0) revert NoTicketsForDraw();

        // Verify there's a pot to distribute
        uint256 pot = s.dailyPot[drawDay];
        if (pot == 0) revert InsufficientPot();

        // Mark draw as executed
        s.drawExecuted[drawDay] = true;
        
        // If VRF is configured, use it
        if (s.entropySource != address(0)) {
            // Use VRF for true randomness
            requestRandomDraw(drawDay, msg.sender);
            // The actual draw will happen in the callback
        } else {
            // Fallback to pseudo-random if VRF not configured
            _performLegacyDraw(drawDay);
        }
    }
    
    /**
     * Legacy draw method using pseudo-random number
     * @param drawDay The day to perform draw for
     */
    function _performLegacyDraw(uint256 drawDay) private {
        Storage storage s = _getStorage();
        
        // Use memory instead of storage reference since we only read
        address[] memory participants = s.ticketsByDay[drawDay];
        uint256 participantCount = participants.length;
        
        uint256 pot = s.dailyPot[drawDay];
        s.dailyPot[drawDay] = 0;

        // Pseudo-random selection
        uint256 winnerIndex;
        unchecked {
            winnerIndex = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp))) % participantCount;
        }
        address winner = participants[winnerIndex];

        // Calculate amounts with unchecked math
        uint256 adminAmount;
        uint256 projectAmount;
        uint256 winnerAmount;
        
        unchecked {
            // Use constants directly to save gas
            uint256 PERCENT_DIVISOR = 100;
            uint256 PROJECT_SHARE = 50;
            
            adminAmount = (pot * s.adminShare) / PERCENT_DIVISOR;
            projectAmount = (pot * PROJECT_SHARE) / PERCENT_DIVISOR;
            winnerAmount = pot - adminAmount - projectAmount;
        }

        // Distribute prizes
        payable(s.openSourceRecipient).transfer(projectAmount);
        payable(s.admin).transfer(adminAmount);
        payable(winner).transfer(winnerAmount);

        emit DailyDrawPerformed(drawDay, winner, winnerAmount);
    }
    
    /**
     * Trigger draw for a specific pool
     * @param poolId The ID of the pool to draw for
     */
    function performPoolDraw(uint256 poolId) external {
        Storage storage s = _getStorage();
        
        // Verify pool exists and is active
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        if (!pool.active) revert PoolNotActive();
        
        // Ensure there's a balance to distribute
        if (pool.ethBalance == 0) revert InsufficientPot();
        
        // If VRF is configured, use it
        if (s.entropySource != address(0)) {
            // Use VRF for true randomness
            requestRandomDraw(poolId, msg.sender);
            // The actual draw will happen in the callback
        } else {
            // Not implemented for legacy mode yet
            revert("Pool draws require VRF");
        }
    }
} 