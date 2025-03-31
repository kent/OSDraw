// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/OSDraw.sol";
import "../src/model/Pool.sol";
import "../src/model/Constants.sol";
import "../src/model/Ticket.sol";
import "../src/interfaces/IVRF.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OSDrawStressTest
 * @dev Stress testing for OSDraw
 * Tests high-volume scenarios to ensure system stability
 */
contract OSDrawStressTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    address[] public users;
    
    // Mock VRF system for testing randomness
    MockVRFSystem public mockVRF;
    
    // Constants for stress testing
    uint256 constant NUM_USERS = 100;
    uint256 constant POOL_TICKET_PRICE = 0.01 ether;
    
    function setUp() public {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        
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
        
        // Create test users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            vm.deal(user, 100 ether);
        }
        
        // Configure VRF entropy source
        vm.prank(admin);
        osDraw.setEntropySource(address(mockVRF));
        
        // Create initial pool for tests
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: POOL_TICKET_PRICE,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
    }
    
    /**
     * @dev Stress test: High volume of daily ticket purchases
     * Tests system stability with a large number of users buying tickets
     */
    function test_stress_highVolumeDailyTickets() public {
        uint256 startGas = gasleft();
        
        // Track total ETH flow and tickets
        uint256 totalSpent = 0;
        uint256 totalTickets = 0;
        
        // Have all users buy tickets of different quantities
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 quantity;
            
            // Distribute different ticket quantities
            if (i % 4 == 0) {
                quantity = 1;
                vm.prank(users[i]);
                osDraw.buyTickets{value: Constants.PRICE_ONE}(quantity);
                totalSpent += Constants.PRICE_ONE;
            } else if (i % 4 == 1) {
                quantity = 5;
                vm.prank(users[i]);
                osDraw.buyTickets{value: Constants.PRICE_FIVE}(quantity);
                totalSpent += Constants.PRICE_FIVE;
            } else if (i % 4 == 2) {
                quantity = 20;
                vm.prank(users[i]);
                osDraw.buyTickets{value: Constants.PRICE_TWENTY}(quantity);
                totalSpent += Constants.PRICE_TWENTY;
            } else {
                quantity = 100;
                vm.prank(users[i]);
                osDraw.buyTickets{value: Constants.PRICE_HUNDRED}(quantity);
                totalSpent += Constants.PRICE_HUNDRED;
            }
            
            totalTickets += quantity;
        }
        
        // Verify system state
        uint256 today = block.timestamp / 1 days;
        assertEq(osDraw.dailyPot(today), totalSpent, "Daily pot doesn't match total spent");
        
        // Check random sample of user ticket counts
        for (uint256 i = 0; i < 10; i++) {
            uint256 userIndex = i * 10; // Check every 10th user
            uint256 expectedQuantity;
            
            if (userIndex % 4 == 0) expectedQuantity = 1;
            else if (userIndex % 4 == 1) expectedQuantity = 5;
            else if (userIndex % 4 == 2) expectedQuantity = 20;
            else expectedQuantity = 100;
            
            assertEq(
                osDraw.getUserTicketCount(users[userIndex], today),
                expectedQuantity,
                "User ticket count incorrect"
            );
        }
        
        // Report gas usage
        uint256 gasUsed = startGas - gasleft();
        console2.log("Gas used for high volume daily tickets:", gasUsed);
    }
    
    /**
     * @dev Stress test: High volume of pool ticket purchases
     * Tests system stability with many users buying pool tickets
     */
    function test_stress_highVolumePoolTickets() public {
        uint256 startGas = gasleft();
        
        // Have all users buy pool tickets
        uint256 totalSpent = 0;
        uint256 totalTickets = 0;
        
        for (uint256 i = 0; i < NUM_USERS; i++) {
            // Each user buys i+1 tickets
            uint256 quantity = (i % 10) + 1;
            uint256 cost = POOL_TICKET_PRICE * quantity;
            
            vm.prank(users[i]);
            osDraw.buyPoolTickets{value: cost}(Constants.POOL_ID_THRESHOLD, quantity);
            
            totalSpent += cost;
            totalTickets += quantity;
        }
        
        // Verify system state
        Pool memory pool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertEq(pool.ethBalance, totalSpent, "Pool balance doesn't match total spent");
        assertEq(pool.totalSold, totalTickets, "Total sold doesn't match expected");
        
        // Check random sample of user ticket counts
        for (uint256 i = 0; i < 10; i++) {
            uint256 userIndex = i * 10; // Check every 10th user
            uint256 expectedQuantity = (userIndex % 10) + 1;
            
            Ticket memory userTicket = osDraw.getUserPoolTickets(
                Constants.POOL_ID_THRESHOLD,
                users[userIndex]
            );
            
            assertEq(
                userTicket.purchased,
                expectedQuantity,
                "User pool ticket count incorrect"
            );
        }
        
        // Report gas usage
        uint256 gasUsed = startGas - gasleft();
        console2.log("Gas used for high volume pool tickets:", gasUsed);
    }
    
    /**
     * @dev Stress test: Large draw with many participants
     * Tests the drawing mechanism with a large number of participants
     * and verifies correct fund distribution
     */
    function test_stress_largeDrawWithManyParticipants() public {
        // Set up - all users buy daily tickets
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        }
        
        // Record balances before draw
        uint256 today = block.timestamp / 1 days;
        uint256 totalPot = osDraw.dailyPot(today);
        uint256 adminBalanceBefore = admin.balance;
        uint256 osBalanceBefore = openSourceRecipient.balance;
        
        // Record all user balances
        uint256[] memory userBalancesBefore = new uint256[](NUM_USERS);
        for (uint256 i = 0; i < NUM_USERS; i++) {
            userBalancesBefore[i] = users[i].balance;
        }
        
        // Move to next day and perform draw
        vm.warp(block.timestamp + 1 days);
        osDraw.performDailyDraw();
        
        // Check that VRF was called
        assertEq(mockVRF.requestCount(), 1, "VRF not called");
        
        // Simulate VRF callback with specific winner (user 50)
        uint256 winnerIndex = 50;
        vm.prank(address(mockVRF));
        osDraw.randomNumberCallback(1, 50); // Pass 50 directly to select user50
        
        // Calculate expected distributions
        uint256 adminAmount = (totalPot * 40) / 100; // 40% admin
        uint256 osAmount = (totalPot * 50) / 100;    // 50% open source
        uint256 winnerAmount = totalPot - adminAmount - osAmount;
        
        // Verify pending payments
        assertEq(osDraw.getPendingPayment(admin), adminAmount, "Admin payment incorrect");
        assertEq(osDraw.getPendingPayment(openSourceRecipient), osAmount, "OS payment incorrect");
        assertEq(osDraw.getPendingPayment(users[winnerIndex]), winnerAmount, "Winner payment incorrect");
        
        // Withdraw and verify balances
        vm.prank(admin);
        osDraw.withdrawPendingPayment();
        
        vm.prank(openSourceRecipient);
        osDraw.withdrawPendingPayment();
        
        vm.prank(users[winnerIndex]);
        osDraw.withdrawPendingPayment();
        
        assertEq(admin.balance, adminBalanceBefore + adminAmount, "Admin balance incorrect");
        assertEq(openSourceRecipient.balance, osBalanceBefore + osAmount, "OS balance incorrect");
        assertEq(users[winnerIndex].balance, userBalancesBefore[winnerIndex] + winnerAmount, "Winner balance incorrect");
        
        // Verify pot was emptied
        assertEq(osDraw.dailyPot(today), 0, "Daily pot not emptied");
    }
    
    /**
     * @dev Stress test: Many pool draws in sequence
     * Tests multiple consecutive pool draws and fund distributions
     */
    function test_stress_multipleConsecutivePoolDraws() public {
        uint256 NUM_DRAWS = 5;
        
        // Create multiple pools
        for (uint256 i = 1; i <= NUM_DRAWS; i++) {
            vm.prank(admin);
            Pool memory poolParams = Pool({
                ticketPrice: POOL_TICKET_PRICE * i, // Increasing prices
                totalSold: 0,
                totalRedeemed: 0,
                ethBalance: 0,
                active: true
            });
            osDraw.createPool(poolParams);
        }
        
        // Users buy tickets in all pools
        for (uint256 poolNum = 0; poolNum < NUM_DRAWS; poolNum++) {
            uint256 poolId = Constants.POOL_ID_THRESHOLD + poolNum;
            
            // Get pool price
            Pool memory pool = osDraw.getPool(poolId);
            
            // Every user buys 1 ticket in each pool
            for (uint256 userIdx = 0; userIdx < 10; userIdx++) {
                vm.prank(users[userIdx]);
                osDraw.buyPoolTickets{value: pool.ticketPrice}(poolId, 1);
            }
        }
        
        // Perform draws for all pools in sequence
        for (uint256 poolNum = 0; poolNum < NUM_DRAWS; poolNum++) {
            uint256 poolId = Constants.POOL_ID_THRESHOLD + poolNum;
            
            // Get pot amount before draw
            Pool memory poolBefore = osDraw.getPool(poolId);
            uint256 poolBalance = poolBefore.ethBalance;
            
            // Perform draw
            osDraw.performPoolDraw(poolId);
            
            // Mock VRF callback - use different winners for each pool
            uint256 winnerIndex = poolNum % 10;
            vm.prank(address(mockVRF));
            osDraw.randomNumberCallback(poolNum + 1, winnerIndex); // Pass winnerIndex directly
            
            // Verify pool is empty after draw
            Pool memory poolAfter = osDraw.getPool(poolId);
            assertEq(poolAfter.ethBalance, 0, "Pool not emptied after draw");
            
            // Calculate expected shares
            uint256 adminAmount = (poolBalance * 40) / 100;
            uint256 osAmount = (poolBalance * 50) / 100;
            uint256 winnerAmount = poolBalance - adminAmount - osAmount;
            
            // Winner should have pending payment
            assertEq(
                osDraw.getPendingPayment(users[winnerIndex]), 
                winnerAmount, 
                "Winner payment incorrect"
            );
            
            // Withdraw payment
            vm.prank(users[winnerIndex]);
            osDraw.withdrawPendingPayment();
        }
        
        // Admin and OS should have pending payments from all draws
        vm.prank(admin);
        osDraw.withdrawPendingPayment();
        
        vm.prank(openSourceRecipient);
        osDraw.withdrawPendingPayment();
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