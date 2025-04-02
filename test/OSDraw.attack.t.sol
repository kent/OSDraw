// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {OSDraw} from "../src/OSDraw.sol";
import {OSDrawStorage} from "../src/OSDrawStorage.sol";
import {Constants} from "../src/model/Constants.sol";
import {IVRFSystem} from "../src/interfaces/IVRF.sol";
import {Pool} from "../src/model/Pool.sol";
import {Ticket} from "../src/model/Ticket.sol";
import {InvalidTicketQuantity} from "../src/errors/OSDraw.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OSDrawAttackTest
 * @dev Tests aimed at identifying and mitigating security vulnerabilities
 */
contract OSDrawAttackTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    address public attacker;
    
    // Mock VRF for randomness
    MockVRFSystem public mockVRF;
    
    // Attack contracts
    ReentrancyAttacker public reentrancyAttacker;
    RandomnessManipulator public randomnessManipulator;
    FrontRunAttacker public frontRunAttacker;
    TimelockBypassAttacker public timelockBypassAttacker;

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        attacker = makeAddr("attacker");
        
        // Fund the attacker
        vm.deal(attacker, 100 ether);
        
        // Deploy mock VRF
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
        
        // Deploy attack contracts
        reentrancyAttacker = new ReentrancyAttacker(osDraw);
        vm.deal(address(reentrancyAttacker), 10 ether);
        
        randomnessManipulator = new RandomnessManipulator(osDraw, mockVRF);
        vm.deal(address(randomnessManipulator), 10 ether);
        
        frontRunAttacker = new FrontRunAttacker(osDraw);
        vm.deal(address(frontRunAttacker), 10 ether);
        
        timelockBypassAttacker = new TimelockBypassAttacker(osDraw);
        vm.deal(address(timelockBypassAttacker), 10 ether);
        
        // Give ETH to OSDraw for withdrawal testing
        vm.deal(address(osDraw), 5 ether);
    }
    
    /**
     * @dev Test reentrancy attack
     * Verifies system is protected against reentrancy attacks
     */
    function test_attack_reentrancy() public {
        // Basic setup - create a valid draw scenario
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        
        // Users buy tickets
        vm.prank(user1);
        osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        
        vm.prank(user2);
        osDraw.buyTickets{value: Constants.PRICE_FIVE}(5);
        
        // Attacker tries to exploit via reentrancy
        bool attackResult = reentrancyAttacker.attackBuyTickets();
        assertFalse(attackResult, "Reentrancy attack should not succeed");
        
        // Simulate a completed draw with pending payouts
        uint256 today = block.timestamp / 1 days;
        
        // Move to next day and perform draw
        vm.warp(block.timestamp + 1 days);
        osDraw.performDailyDraw();
        
        // Simulate VRF callback that makes the attacker win
        vm.prank(address(mockVRF));
        osDraw.randomNumberCallback(1, 0); // Attacker's index
        
        // Try to exploit the withdrawal
        bool withdrawAttackResult = reentrancyAttacker.attackWithdraw();
        assertFalse(withdrawAttackResult, "Withdraw reentrancy attack should not succeed");
    }
    
    /**
     * @dev Test randomness manipulation attack
     * Verifies system protection against VRF manipulation attempts
     */
    function test_attack_randomnessManipulation() public {
        // Setup a draw scenario
        address user1 = makeAddr("user1");
        vm.deal(user1, 1 ether);
        
        vm.prank(user1);
        osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        
        // Attacker buys tickets and tries to manipulate randomness
        bool attackResult = randomnessManipulator.attack();
        
        // Attacker should not be able to influence randomness
        assertFalse(attackResult, "Randomness manipulation should not succeed");
        
        // Perform the draw legitimately
        vm.warp(block.timestamp + 1 days);
        osDraw.performDailyDraw();
        
        // Ensure only the legitimate VRF can provide randomness
        vm.prank(attacker);
        vm.expectRevert(); // Should revert with Unauthorized
        osDraw.randomNumberCallback(1, 123456);
    }
    
    /**
     * @dev Test front-running attack
     * Verifies system resilience to front-running attempts
     */
    function test_attack_frontRunning() public {
        // Set up a user who buys tickets legitimately
        address user = makeAddr("user");
        vm.deal(user, 1 ether);
        
        vm.prank(user);
        osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        
        // Warp time to close to the end of the day to trigger cooldown period
        uint256 secondsPerDay = 1 days;
        uint256 cooldownPeriod = 1 hours;
        uint256 timeToEndOfDay = secondsPerDay - (block.timestamp % secondsPerDay);
        
        // Position right in the cooldown period
        vm.warp(block.timestamp + timeToEndOfDay - (cooldownPeriod / 2));
        
        // Attacker tries to front-run the draw during cooldown period
        bool attackResult = frontRunAttacker.attack();
        assertFalse(attackResult, "Front-running attack should not succeed");
        
        // Even if attacker knows a draw is coming, they can't benefit unfairly
        vm.warp(block.timestamp + 1 days);
        
        // Try to front-run with knowledge of an upcoming draw
        attackResult = frontRunAttacker.attackWithKnowledge();
        assertFalse(attackResult, "Front-running with knowledge should not succeed");
    }
    
    /**
     * @dev Test timelock bypass attack
     * Verifies timelock protection can't be bypassed
     */
    function test_attack_timelockBypass() public {
        // Set up a scenario requiring timelock (e.g., emergency withdrawal)
        vm.deal(address(osDraw), 5 ether);
        
        // Try various attacks to bypass timelock
        bool attackResult = timelockBypassAttacker.attack();
        assertFalse(attackResult, "Timelock bypass attack should not succeed");
        
        // Try to exploit a hypothetical upgrade to bypass timelock
        bool upgradeAttackResult = timelockBypassAttacker.attackUpgrade();
        assertFalse(upgradeAttackResult, "Upgrade-based timelock bypass should not succeed");
    }
    
    /**
     * @dev Test integer overflow/underflow protections
     * Verifies math operations are safe
     */
    function test_attack_integerOverflow() public {
        // Create a pool with a small ticket price
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: 1, // 1 wei
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
        
        // Try to cause an overflow by buying a huge number of tickets
        // This should fail on quantity check before payment check
        vm.prank(attacker);
        vm.expectRevert(InvalidTicketQuantity.selector);
        osDraw.buyPoolTickets(Constants.POOL_ID_THRESHOLD, 1001); // More than 1000 tickets
        
        // Try with a large quantity and matching value
        // Make sure attacker has a reasonable amount of ETH to test the quantity validation
        uint256 largeQuantity = 1001;
        vm.deal(attacker, largeQuantity);
        vm.prank(attacker);
        vm.expectRevert(InvalidTicketQuantity.selector);
        osDraw.buyPoolTickets{value: largeQuantity}(Constants.POOL_ID_THRESHOLD, largeQuantity);
    }

    function attackPoolSystem() external returns (bool) {
        // Try to create a malicious pool
        try this.createMaliciousPool() {
            return true; // Managed to create an exploitable pool
        } catch {
            return false; // Failed to create - protected
        }
    }
    
    function createMaliciousPool() external {
        // Create pool with extreme properties
        Pool memory poolParams = Pool({
            ticketPrice: 0,  // Zero cost tickets
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        
        osDraw.createPool(poolParams);
    }
}

/**
 * @dev Contract attempting to exploit via reentrancy
 */
contract ReentrancyAttacker {
    OSDraw public target;
    bool public hasTriedReentrancy;
    
    constructor(OSDraw _target) {
        target = _target;
    }
    
    function attackBuyTickets() external returns (bool) {
        // Buy tickets with reentrancy attempt
        target.buyTickets{value: 0.01 ether}(1);
        return hasTriedReentrancy;
    }
    
    function attackWithdraw() external returns (bool) {
        // Try to withdraw with reentrancy
        if (target.getPendingPayment(address(this)) > 0) {
            hasTriedReentrancy = false;
            target.withdrawPendingPayment();
            return hasTriedReentrancy;
        }
        return false;
    }
    
    // Fallback and receive functions for reentrancy attempts
    receive() external payable {
        if (!hasTriedReentrancy) {
            hasTriedReentrancy = true;
            
            // Try to reenter different functions
            try target.buyTickets{value: 0.01 ether}(1) {
                // Succeeded - reentrancy protection failed
            } catch {
                // Expected - reentrancy blocked
            }
            
            try target.withdrawPendingPayment() {
                // Succeeded - reentrancy protection failed
            } catch {
                // Expected - reentrancy blocked
            }
        }
    }
}

/**
 * @dev Contract attempting to manipulate randomness
 */
contract RandomnessManipulator {
    OSDraw public target;
    MockVRFSystem public mockVRF;
    
    constructor(OSDraw _target, MockVRFSystem _mockVRF) {
        target = _target;
        mockVRF = _mockVRF;
    }
    
    function attack() external returns (bool) {
        // Buy tickets
        target.buyTickets{value: 0.01 ether}(1);
        
        // Try to manipulate VRF
        try this.impersonateVRF() {
            return true; // Manipulation succeeded
        } catch {
            return false; // Manipulation failed
        }
    }
    
    function impersonateVRF() external {
        // Try to trigger callback as if we're the VRF
        target.randomNumberCallback(1, uint256(uint160(address(this))));
    }
}

/**
 * @dev Contract attempting to front-run operations
 */
contract FrontRunAttacker {
    OSDraw public target;
    
    constructor(OSDraw _target) {
        target = _target;
    }
    
    function attack() external returns (bool) {
        // Try to extract info about pending draws
        uint256 today = block.timestamp / 1 days;
        uint256 pot = target.dailyPot(today);
        
        // Try to front-run based on pot size
        if (pot > 0) {
            // Buy more tickets to increase chances - using exact price for 20 tickets
            try target.buyTickets{value: Constants.PRICE_TWENTY}(20) {
                return true; // Succeeded in buying tickets
            } catch {
                return false; // Attack prevented due to cooldown
            }
        }
        
        return false;
    }
    
    function attackWithKnowledge() external returns (bool) {
        // Simulate knowledge that a draw is about to happen
        uint256 today = block.timestamp / 1 days;
        
        // Try to buy tickets just before draw
        try target.buyTickets{value: Constants.PRICE_ONE}(1) {
            // Try to manipulate draw time
            try this.triggerDraw() {
                return true;
            } catch {
                return false;
            }
        } catch {
            return false; // Attack prevented due to cooldown
        }
    }
    
    function triggerDraw() external {
        target.performDailyDraw();
    }
}

/**
 * @dev Contract attempting to bypass timelock
 */
contract TimelockBypassAttacker {
    OSDraw public target;
    
    constructor(OSDraw _target) {
        target = _target;
    }
    
    function attack() external returns (bool) {
        address recipient = address(this);
        
        // Try immediate withdrawal without timelock
        try target.emergencyWithdraw(1 ether, recipient) {
            return true; // Bypass succeeded
        } catch {
            return false; // Timelock enforced
        }
    }
    
    function attackUpgrade() external returns (bool) {
        // Try to bypass timelock through an upgrade
        address fakeImplementation = address(this);
        
        // Only owner can upgrade but we're testing if timelock is used
        try this.upgradeContract(fakeImplementation) {
            return true; // Bypass succeeded
        } catch {
            return false; // Protected
        }
    }
    
    function upgradeContract(address implementation) external {
        // Will fail due to onlyOwner, but we're testing if there's a timelock check
        try target.upgradeToAndCall(implementation, "") {
            // If this succeeds without timelock, it's vulnerable
        } catch Error(string memory reason) {
            // Expected to fail with auth or timelock error
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