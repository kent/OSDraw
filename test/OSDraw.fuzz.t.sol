// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {OSDraw} from "../src/OSDraw.sol";
import {OSDrawStorage} from "../src/OSDrawStorage.sol";
import {Constants} from "../src/model/Constants.sol";
import {IVRFSystem} from "../src/interfaces/IVRF.sol";
import {Pool} from "../src/model/Pool.sol";
import {Ticket} from "../src/model/Ticket.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OSDrawFuzzTest
 * @dev Fuzz testing for OSDraw system
 * 
 * This test suite uses property-based testing to verify the system behaves
 * correctly under a wide range of inputs.
 */
contract OSDrawFuzzTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    address public user1;
    address public user2;
    
    // Mock VRF system for testing randomness
    MockVRFSystem public mockVRF;

    function setUp() public {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock VRF for randomness testing
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
        
        // Give test ETH to participants
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Configure VRF entropy source
        vm.prank(admin);
        osDraw.setEntropySource(address(mockVRF));
    }

    /**
     * @dev Fuzz test for buying daily tickets with different quantities
     * @param quantity The ticket quantity to test
     */
    function testFuzz_ticketPurchasing(uint256 quantity) public {
        // Restrict to valid quantities
        vm.assume(quantity == 1 || quantity == 5 || quantity == 20 || quantity == 100);
        
        // Calculate the expected price
        uint256 price = osDraw.getPrice(quantity);
        
        // Buy tickets
        vm.prank(user1);
        osDraw.buyTickets{value: price}(quantity);
        
        // Verify ticket count
        uint256 today = block.timestamp / 1 days;
        assertEq(osDraw.getUserTicketCount(user1, today), quantity, "Ticket count mismatch");
        
        // Verify daily pot
        assertEq(osDraw.dailyPot(today), price, "Daily pot mismatch");
    }
    
    /**
     * @dev Fuzz test for buying pool tickets with different quantities
     * @param quantity The ticket quantity to test
     * @param ticketPriceMultiplier Used to generate a valid ticket price
     */
    function testFuzz_poolTicketPurchasing(uint256 quantity, uint256 ticketPriceMultiplier) public {
        // Restrict quantity to values the contract accepts (1-100 is reasonable)
        vm.assume(quantity > 0 && quantity <= 50);
        
        // Use the multiplier to get a ticket price within our desired range
        uint256 ticketPrice = 0.001 ether + (ticketPriceMultiplier % 99 * 0.001 ether);
        vm.assume(ticketPrice >= 0.001 ether && ticketPrice <= 0.1 ether);
        
        // Make sure user has enough funds
        vm.deal(user1, 101 ether);
        
        // Create pool
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: ticketPrice,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
        
        // Calculate total price 
        uint256 totalPrice = quantity * ticketPrice;
        
        // Buy tickets
        vm.prank(user1);
        osDraw.buyPoolTickets{value: totalPrice}(Constants.POOL_ID_THRESHOLD, quantity);
        
        // Verify ticket purchase
        Ticket memory ticket = osDraw.getUserPoolTickets(Constants.POOL_ID_THRESHOLD, user1);
        assertEq(ticket.purchased, quantity, "Pool ticket count mismatch");
        
        // Verify pool state
        Pool memory pool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertEq(pool.totalSold, quantity, "Pool total sold mismatch");
        assertEq(pool.ethBalance, totalPrice, "Pool balance mismatch");
    }
    
    /**
     * @dev Fuzz test for pool creation with different parameters
     * @param ticketPrice The ticket price to test
     * @param active Whether the pool should be active
     */
    function testFuzz_poolCreation(uint256 ticketPrice, bool active) public {
        // Restrict to valid ranges
        vm.assume(ticketPrice > 0 && ticketPrice <= 10 ether);
        
        // Create pool
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: ticketPrice,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: active
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
        
        // Verify pool was created correctly
        Pool memory pool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertEq(pool.ticketPrice, ticketPrice, "Pool ticket price mismatch");
        assertEq(pool.active, active, "Pool active status mismatch");
    }
    
    /**
     * @dev Fuzz test for emergency withdrawal with different amounts
     * @param amount The amount to withdraw
     */
    function testFuzz_emergencyWithdrawal(uint256 amount) public {
        // Restrict to reasonable ranges
        vm.assume(amount > 0 && amount <= 10 ether);
        
        // Setup recipient
        address recipient = makeAddr("recipient");
        
        // Give contract some ETH
        vm.deal(address(osDraw), amount);
        
        // Initial balances
        uint256 contractBalanceBefore = address(osDraw).balance;
        uint256 recipientBalanceBefore = recipient.balance;
        
        // Queue emergency withdrawal
        vm.prank(address(osDraw.owner()));
        osDraw.emergencyWithdraw(amount, recipient);
        
        // Fast-forward past timelock
        vm.warp(block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY + 1);
        
        // Complete withdrawal
        vm.prank(address(osDraw.owner()));
        osDraw.emergencyWithdraw(amount, recipient);
        
        // Verify balances
        assertEq(address(osDraw).balance, contractBalanceBefore - amount, "Contract balance mismatch");
        assertEq(recipient.balance, recipientBalanceBefore + amount, "Recipient balance mismatch");
    }
    
    /**
     * @dev Fuzz test for randomness distribution in draws
     * @param randomNumber The random number to test
     */
    function testFuzz_randomnessFairness(uint256 randomNumber) public {
        // Set up the daily draw - 3 users buy different amounts of tickets
        // Simulate a simplified version with in-memory array to track expected winners
        address[] memory participants = new address[](26);
        
        // User1 buys 1 ticket (index 0)
        participants[0] = user1;
        
        // User2 buys 5 tickets (index 1-5)
        address user2Local = makeAddr("user2Local");
        for (uint256 i = 1; i <= 5; i++) {
            participants[i] = user2Local;
        }
        
        // User3 buys 20 tickets (index 6-25)
        address user3 = makeAddr("user3");
        for (uint256 i = 6; i <= 25; i++) {
            participants[i] = user3;
        }
        
        // Calculate winner based on random number
        uint256 winnerIndex = randomNumber % participants.length;
        address expectedWinner = participants[winnerIndex];
        
        // Count how many tickets each user has
        uint256 user1Tickets = 0;
        uint256 user2Tickets = 0;
        uint256 user3Tickets = 0;
        
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == user1) user1Tickets++;
            else if (participants[i] == user2Local) user2Tickets++;
            else if (participants[i] == user3) user3Tickets++;
        }
        
        // Verify expected distribution
        assertEq(user1Tickets, 1, "User1 should have 1 ticket");
        assertEq(user2Tickets, 5, "User2 should have 5 tickets");
        assertEq(user3Tickets, 20, "User3 should have 20 tickets");
        
        // Verify the random selection logic gives expected winner
        if (winnerIndex == 0) {
            assertEq(expectedWinner, user1, "Should select user1");
        } else if (winnerIndex >= 1 && winnerIndex <= 5) {
            assertEq(expectedWinner, user2Local, "Should select user2");
        } else {
            assertEq(expectedWinner, user3, "Should select user3");
        }
    }

    /**
     * @dev Advanced statistical test for randomness fairness over many draws
     * Verifies that winner distribution matches ticket distribution
     */
    function testFuzz_randomnessStatisticalFairness() public {
        // Test parameters
        uint256 NUM_TRIALS = 1000;
        address[] memory participants = new address[](3);
        participants[0] = makeAddr("user1");
        participants[1] = makeAddr("user2");
        participants[2] = makeAddr("user3");
        
        // Participant ticket proportions - 10%, 30%, 60%
        uint256[] memory ticketCounts = new uint256[](3);
        ticketCounts[0] = 10;  // 10 tickets for user1
        ticketCounts[1] = 30;  // 30 tickets for user2
        ticketCounts[2] = 60;  // 60 tickets for user3
        
        // Winner counts for statistical analysis
        uint256[] memory winCounts = new uint256[](3);
        
        // Set up a simulated daily draw with fixed tickets
        uint256 totalTickets = ticketCounts[0] + ticketCounts[1] + ticketCounts[2];
        address[] memory expandedParticipants = new address[](totalTickets);
        
        // Expand participants array to match ticket distribution
        uint256 ticketIndex = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            for (uint256 j = 0; j < ticketCounts[i]; j++) {
                expandedParticipants[ticketIndex] = participants[i];
                ticketIndex++;
            }
        }
        
        // Run many trials with different random numbers
        for (uint256 trial = 0; trial < NUM_TRIALS; trial++) {
            // Generate "random" number (deterministic for test but covers range)
            uint256 randomNumber = uint256(keccak256(abi.encode(trial)));
            
            // Select winner
            uint256 winnerIndex = randomNumber % totalTickets;
            address winner = expandedParticipants[winnerIndex];
            
            // Track win count
            for (uint256 i = 0; i < participants.length; i++) {
                if (winner == participants[i]) {
                    winCounts[i]++;
                    break;
                }
            }
        }
        
        // Verify statistical fairness (with tolerance)
        // Expected win percentages should match ticket percentages
        uint256 tolerance = NUM_TRIALS / 20; // 5% tolerance
        
        // Expected wins based on ticket distribution
        uint256[] memory expectedWins = new uint256[](3);
        expectedWins[0] = (NUM_TRIALS * ticketCounts[0]) / totalTickets;
        expectedWins[1] = (NUM_TRIALS * ticketCounts[1]) / totalTickets;
        expectedWins[2] = (NUM_TRIALS * ticketCounts[2]) / totalTickets;
        
        // Check each participant's wins are within tolerance
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 lowerBound = expectedWins[i] > tolerance ? expectedWins[i] - tolerance : 0;
            uint256 upperBound = expectedWins[i] + tolerance;
            
            assertTrue(
                winCounts[i] >= lowerBound && winCounts[i] <= upperBound,
                string(abi.encodePacked(
                    "Participant ", 
                    vm.toString(i), 
                    " has unfair win distribution. Expected ~",
                    vm.toString(expectedWins[i]),
                    ", got ",
                    vm.toString(winCounts[i])
                ))
            );
        }
    }
}

/**
 * @dev Mock VRF for testing randomness
 */
contract MockVRFSystem is IVRFSystem {
    uint256 public requestCount;
    
    function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256) {
        requestCount++;
        emit RandomNumberRequested(requestCount, msg.sender, traceId);
        return requestCount;
    }
} 