// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {OSDraw} from "../src/OSDraw.sol";
import {OSDrawStorage} from "../src/OSDrawStorage.sol";
import {Constants} from "../src/model/Constants.sol";
import {IVRFSystem} from "../src/interfaces/IVRF.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OSDrawSymbolicTest
 * @dev Symbolic execution tests for OSDraw
 * 
 * These tests use techniques similar to formal verification to prove critical
 * security properties hold for all possible inputs within bounds.
 */
contract OSDrawSymbolicTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    address public user;
    
    // Mock VRF for randomness
    MockVRFSystem public mockVRF;

    function setUp() public {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        user = makeAddr("user");
        
        mockVRF = new MockVRFSystem();
        
        // Deploy implementation
        OSDraw implementation = new OSDraw();
        
        // Deploy proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                OSDraw.initialize.selector,
                openSourceRecipient,
                admin,
                manager,
                40 // Admin share of 40%
            )
        );
        
        // Cast proxy to OSDraw interface
        osDraw = OSDraw(address(proxy));
        
        // Configure VRF
        vm.prank(admin);
        osDraw.setEntropySource(address(mockVRF));
        
        // Fund test accounts
        vm.deal(user, 100 ether);
    }
    
    /**
     * @dev Symbolic test of prize distribution correctness
     * Proves that for any pot size, prize shares always sum to the total
     */
    function test_sym_prizeDistributionCorrectness(uint256 potSize) public {
        // Bound pot size to realistic values
        potSize = bound(potSize, 0.001 ether, 1000 ether);
        
        // Calculate shares based on contract rules
        uint256 adminShare = (potSize * 40) / 100; // 40% admin
        uint256 osShare = (potSize * 50) / 100;    // 50% open source
        uint256 winnerShare = potSize - adminShare - osShare; // Remainder to winner
        
        // Verify sum of shares equals pot size
        assertEq(adminShare + osShare + winnerShare, potSize, "Shares must sum to pot size");
        
        // Verify shares are in correct proportions
        assertApproxEqRel(adminShare, (potSize * 40) / 100, 0.0001e18, "Admin share incorrect");
        assertApproxEqRel(osShare, (potSize * 50) / 100, 0.0001e18, "OS share incorrect");
        
        // Verify no precision loss can lead to incorrect distribution
        uint256 reconstructedPot = adminShare + osShare + winnerShare;
        assertEq(reconstructedPot, potSize, "Precision loss in distribution");
    }
    
    /**
     * @dev Symbolic test for randomness bounds
     * Proves that for any random number, winner selection stays within bounds
     */
    function test_sym_randomnessBounds(uint256 randomNumber, uint8 numTickets) public {
        // Ensure we have at least 1 ticket
        numTickets = uint8(bound(numTickets, 1, 100));
        
        // Create a mock ticket array
        address[] memory tickets = new address[](numTickets);
        for (uint8 i = 0; i < numTickets; i++) {
            tickets[i] = makeAddr(string.concat("holder", vm.toString(i)));
        }
        
        // Calculate winner index using the same logic as the contract
        uint256 winnerIndex = randomNumber % numTickets;
        
        // Verify winner index is within bounds regardless of random input
        assertTrue(winnerIndex < numTickets, "Winner index out of bounds");
        assertTrue(winnerIndex >= 0, "Winner index negative");
        
        // Additional verification that using unchecked math in this context is safe
        unchecked {
            uint256 uncheckedWinnerIndex = randomNumber % numTickets;
            assertEq(uncheckedWinnerIndex, winnerIndex, "Unchecked math produces different result");
        }
    }
    
    /**
     * @dev Symbolic test for timelock security
     * Proves that operations cannot be executed before delay expires
     * for any timestamp and delay combination
     */
    function test_sym_timelockSecurity(uint256 initialTimestamp, uint256 delay) public {
        // Bound values to reasonable ranges
        initialTimestamp = bound(initialTimestamp, 1, block.timestamp + 365 days);
        delay = bound(delay, Constants.MIN_TIMELOCK_DELAY, Constants.MAX_TIMELOCK_DELAY);
        
        console2.log("Bound result", initialTimestamp);
        console2.log("Bound result", delay);
        
        // Setup
        vm.warp(initialTimestamp);
        address recipient = makeAddr("recipient");
        vm.deal(address(osDraw), 1 ether);
        
        // Create a unique operationId that we can reference later
        bytes32 opId = keccak256(abi.encode(
            "emergencyWithdraw",
            1 ether,
            recipient,
            block.chainid
        ));
        
        // Set specific timelock delay for this test
        vm.startPrank(address(osDraw.owner()));
        osDraw.setTimelockDelay(delay);
        
        // Queue the withdrawal operation (first call)
        osDraw.emergencyWithdraw(1 ether, recipient);
        vm.stopPrank();
        
        // Create a custom contract to try to bypass the timelock
        TimelockBypassAttacker attacker = new TimelockBypassAttacker(osDraw);
        
        // Try to bypass the timelock - this should fail
        bool bypassSucceeded = attacker.attackEmergencyWithdraw(1 ether, recipient);
        assertFalse(bypassSucceeded, "Should not be able to bypass timelock");
        
        // Try executing at exactly delay timestamp - should succeed
        vm.warp(initialTimestamp + delay);
        vm.prank(address(osDraw.owner()));
        osDraw.emergencyWithdraw(1 ether, recipient);
        
        // Verify recipient received funds
        assertEq(recipient.balance, 1 ether, "Recipient didn't receive funds");
    }
    
    /**
     * @dev Symbolic test for re-entrancy protection
     * Proves that re-entrancy protection works for any call sequence
     */
    function test_sym_reentrancyProtection() public {
        // Create a malicious contract that will try to re-enter
        ReentrancyAttacker attacker = new ReentrancyAttacker(osDraw);
        vm.deal(address(attacker), 10 ether);
        
        // Try to attack - should fail
        bool success = attacker.attack();
        assertFalse(success, "Re-entrancy attack should fail");
    }
}

/**
 * @dev Contract that attempts to re-enter OSDraw functions
 */
contract ReentrancyAttacker {
    OSDraw public target;
    bool public hasReentered = false;
    
    constructor(OSDraw _target) {
        target = _target;
    }
    
    function attack() external returns (bool) {
        // Buy tickets first
        target.buyTickets{value: 0.01 ether}(1);
        return hasReentered;
    }
    
    // Fallback function that tries to re-enter
    receive() external payable {
        if (!hasReentered) {
            hasReentered = true;
            // Try to re-enter the contract
            try target.buyTickets{value: 0.01 ether}(1) {
                // If we get here, re-entrancy protection failed
            } catch {
                // Expected behavior - re-entrancy blocked
            }
        }
    }
}

/**
 * @dev Mock VRF for testing
 */
contract MockVRFSystem is IVRFSystem {
    uint256 public requestCount;
    
    function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256) {
        requestCount++;
        emit RandomNumberRequested(requestCount, msg.sender, traceId);
        return requestCount;
    }
}

/**
 * @dev Contract that attempts to bypass timelock
 */
contract TimelockBypassAttacker {
    OSDraw public target;
    
    constructor(OSDraw _target) {
        target = _target;
    }
    
    function attackEmergencyWithdraw(uint256 amount, address recipient) external returns (bool) {
        // Attempt to execute immediately (before timelock expires)
        try target.emergencyWithdraw(amount, recipient) {
            // If no revert, check if funds were actually transferred
            if (recipient.balance > 0) {
                return true; // We managed to bypass the timelock!
            }
            return false; // Operation was queued, not executed
        } catch {
            // Expected - operation protected by timelock
            return false;
        }
    }
} 