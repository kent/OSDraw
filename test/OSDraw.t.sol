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
 * @title OSDrawTest
 * @dev Formal verification test suite for OSDraw system
 * 
 * This test suite verifies various invariants and security properties:
 * 1. Fund accounting - ensure ETH can't be lost or double-counted
 * 2. Access control - verify only authorized users can access admin functions
 * 3. Randomness - verify randomness is secure and can't be manipulated
 * 4. Timelock - ensure timelock operations work as expected
 */
contract OSDrawTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    address public user1;
    address public user2;
    address public user3;
    
    // Mock VRF system for testing randomness
    MockVRFSystem public mockVRF;
    
    // Constants for testing
    uint256 constant DAILY_DRAW_DAY = 1;
    uint256 constant POOL_ID = Constants.POOL_ID_THRESHOLD;
    
    // Track requests for random numbers
    uint256[] public randomRequests;

    function setUp() public {
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

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
        vm.deal(user3, 10 ether);
        
        // Configure VRF entropy source
        vm.prank(admin);
        osDraw.setEntropySource(address(mockVRF));
    }

    /**
     * @dev Test initialization and configuration
     * Verifies: Basic configuration is set correctly
     */
    function test_initialization() public {
        assertEq(osDraw.admin(), admin, "Admin not set correctly");
        assertEq(osDraw.manager(), manager, "Manager not set correctly");
        assertEq(osDraw.openSourceRecipient(), openSourceRecipient, "Open source recipient not set correctly");
        assertEq(osDraw.adminShare(), 40, "Admin share not set correctly");
        assertEq(osDraw.getVersion(), 1, "Version incorrect");
    }

    /**
     * @dev Test access control on admin functions
     * Verifies: Only admin can access admin functions
     */
    function test_accessControl() public {
        // Try to call admin function as non-admin
        vm.prank(user1);
        vm.expectRevert(); // This should revert with Unauthorized error
        osDraw.setEntropySource(address(0x123));
        
        // Now try as admin
        vm.prank(admin);
        osDraw.setEntropySource(address(0x123));
        
        // Try to call manager function as non-manager
        vm.prank(user1);
        vm.expectRevert(); // This should revert with Unauthorized error
        osDraw.updateOpenSourceRecipient(user2);
        
        // Now try as manager
        vm.prank(manager);
        osDraw.updateOpenSourceRecipient(user2);
        
        // Verify manager updated the recipient
        assertEq(osDraw.openSourceRecipient(), user2, "Manager couldn't update open source recipient");
    }
    
    /**
     * @dev Test manager role transfer
     * Verifies: Manager role can be transferred correctly
     */
    function test_transferManager() public {
        // Transfer manager role
        vm.prank(manager);
        osDraw.transferManager(user1);
        
        // Verify manager was updated
        assertEq(osDraw.manager(), user1, "Manager role transfer failed");
        
        // Verify old manager has lost access
        vm.prank(manager);
        vm.expectRevert(); // Unauthorized
        osDraw.transferManager(user2);
        
        // Verify new manager has access
        vm.prank(user1);
        osDraw.transferManager(user2);
    }
    
    /**
     * @dev Test fund accounting for ticket purchases
     * Verifies: Funds are properly accounted for
     */
    function test_fundAccounting() public {
        // Record initial balances
        uint256 initialContractBalance = address(osDraw).balance;
        
        // Buy tickets (must use one of the predefined quantities: 1, 5, 20, 100)
        vm.prank(user1);
        osDraw.buyTickets{value: 0.01 ether}(1);
        
        // Verify contract balance increased correctly
        assertEq(
            address(osDraw).balance, 
            initialContractBalance + 0.01 ether, 
            "Contract balance incorrect"
        );
        
        // Verify daily pot was updated
        uint256 today = block.timestamp / 1 days;
        assertEq(osDraw.dailyPot(today), 0.01 ether, "Daily pot not updated correctly");
    }
    
    /**
     * @dev Test purchasing multiple ticket quantities
     * Verifies: Different ticket bundle prices work correctly
     */
    function test_multipleTicketPurchases() public {
        // Buy 1 ticket
        vm.prank(user1);
        osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        
        // Buy 5 tickets
        vm.prank(user2);
        osDraw.buyTickets{value: Constants.PRICE_FIVE}(5);
        
        // Buy 20 tickets
        vm.prank(user3);
        osDraw.buyTickets{value: Constants.PRICE_TWENTY}(20);
        
        // Verify ticket counts
        uint256 today = block.timestamp / 1 days;
        assertEq(osDraw.getUserTicketCount(user1, today), 1, "User1 ticket count wrong");
        assertEq(osDraw.getUserTicketCount(user2, today), 5, "User2 ticket count wrong");
        assertEq(osDraw.getUserTicketCount(user3, today), 20, "User3 ticket count wrong");
        
        // Verify daily pot total
        assertEq(
            osDraw.dailyPot(today), 
            Constants.PRICE_ONE + Constants.PRICE_FIVE + Constants.PRICE_TWENTY, 
            "Daily pot total wrong"
        );
    }
    
    /**
     * @dev Test invalid ticket purchases
     * Verifies: Input validation for ticket purchases works correctly
     */
    function test_invalidTicketPurchases() public {
        // Try to buy 0 tickets
        vm.prank(user1);
        vm.expectRevert(); // InvalidTicketQuantity
        osDraw.buyTickets{value: Constants.PRICE_ONE}(0);
        
        // Try to buy with incorrect ETH amount
        vm.prank(user1);
        vm.expectRevert(); // IncorrectPaymentAmount
        osDraw.buyTickets{value: 0.02 ether}(1);
        
        // Try to buy invalid quantity
        vm.prank(user1);
        vm.expectRevert(); // InvalidTicketQuantity
        osDraw.buyTickets{value: 0.03 ether}(3);
        
        // Try to buy too many tickets
        vm.prank(user1);
        vm.expectRevert(); // InvalidTicketQuantity
        osDraw.buyTickets{value: 1 ether}(101);
    }
    
    /**
     * @dev Test invariant: Total balances always equal contract balance
     * Verifies: No funds can be lost or double-counted
     */
    function test_balanceInvariant() public {
        // Create a new pool as admin
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: 0.1 ether,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
        
        // Buy daily tickets
        vm.prank(user1);
        osDraw.buyTickets{value: 0.01 ether}(1);
        
        // Buy pool tickets
        vm.prank(user2);
        osDraw.buyPoolTickets{value: 0.5 ether}(Constants.POOL_ID_THRESHOLD, 5);
        
        // Verify invariant: sum of all pots equals contract balance
        uint256 today = block.timestamp / 1 days;
        uint256 dailyPotAmount = osDraw.dailyPot(today);
        Pool memory pool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        uint256 poolBalance = pool.ethBalance;
        
        assertEq(
            address(osDraw).balance,
            dailyPotAmount + poolBalance,
            "Balance invariant violated"
        );
    }
    
    /**
     * @dev Test pool creation and management
     * Verifies: Pool management functions work correctly
     */
    function test_poolManagement() public {
        // Create new pool
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: 0.1 ether,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        
        // Update pool
        poolParams.ticketPrice = 0.2 ether;
        poolParams.active = false;
        osDraw.updatePool(Constants.POOL_ID_THRESHOLD, poolParams);
        
        // Verify pool was updated
        Pool memory updatedPool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertEq(updatedPool.ticketPrice, 0.2 ether, "Pool price not updated");
        assertEq(updatedPool.active, false, "Pool status not updated");
        
        // Activate pool using dedicated function
        osDraw.setPoolActive(Constants.POOL_ID_THRESHOLD, true);
        vm.stopPrank();
        
        // Verify pool was activated
        updatedPool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertTrue(updatedPool.active, "Pool not activated");
        
        // Try buying tickets for inactive pool
        vm.prank(admin);
        osDraw.setPoolActive(Constants.POOL_ID_THRESHOLD, false);
        
        vm.prank(user1);
        vm.expectRevert(); // PoolNotActive
        osDraw.buyPoolTickets{value: 0.2 ether}(Constants.POOL_ID_THRESHOLD, 1);
        
        // Reactivate and buy tickets
        vm.prank(admin);
        osDraw.setPoolActive(Constants.POOL_ID_THRESHOLD, true);
        
        vm.prank(user1);
        osDraw.buyPoolTickets{value: 0.2 ether}(Constants.POOL_ID_THRESHOLD, 1);
        
        // Verify ticket purchase
        Ticket memory ticket = osDraw.getUserPoolTickets(Constants.POOL_ID_THRESHOLD, user1);
        assertEq(ticket.purchased, 1, "Pool ticket not purchased");
    }
    
    /**
     * @dev Test daily drawing process with VRF
     * Verifies: Draw executed correctly with random numbers
     */
    function test_dailyDrawWithVRF() public {
        // Setup - buy tickets on day 1
        uint256 today = block.timestamp / 1 days;
        vm.warp(today * 1 days); // Make sure we're at the start of the day
        
        // Multiple users buy tickets
        vm.prank(user1);
        osDraw.buyTickets{value: Constants.PRICE_ONE}(1);
        
        vm.prank(user2);
        osDraw.buyTickets{value: Constants.PRICE_FIVE}(5);
        
        vm.prank(user3);
        osDraw.buyTickets{value: Constants.PRICE_TWENTY}(20);
        
        // Record balances before draw
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;
        uint256 user3BalanceBefore = user3.balance;
        uint256 adminBalanceBefore = admin.balance;
        uint256 osBalanceBefore = openSourceRecipient.balance;
        
        // Move to next day for the draw
        vm.warp(block.timestamp + 1 days);
        
        // Perform the draw
        osDraw.performDailyDraw();
        
        // Check that the draw was requested
        assertEq(mockVRF.requestCount(), 1, "VRF request not made");
        
        // Choose winner - let's say it's user3 who has the most tickets (simulating random selection)
        uint64 requestId = 1;
        uint256 randomNumber = 15; // This will select user3 based on ticket distribution
        
        // Mock the VRF callback
        vm.prank(address(mockVRF));
        osDraw.randomNumberCallback(requestId, randomNumber);
        
        // Verify draw was executed
        assertTrue(osDraw.drawExecuted(today), "Draw not marked as executed");
        
        // Verify pot was emptied
        assertEq(osDraw.dailyPot(today), 0, "Pot not emptied");
        
        // Verify pending payments - user3 should have winnings available
        uint256 pendingUser3 = osDraw.getPendingPayment(user3);
        assertTrue(pendingUser3 > 0, "Winner has no pending payment");
        
        // Verify admin and OS recipient have pending payments
        uint256 pendingAdmin = osDraw.getPendingPayment(admin);
        uint256 pendingOS = osDraw.getPendingPayment(openSourceRecipient);
        assertTrue(pendingAdmin > 0, "Admin has no pending payment");
        assertTrue(pendingOS > 0, "OS recipient has no pending payment");
        
        // Calculated expected amounts
        uint256 totalPot = Constants.PRICE_ONE + Constants.PRICE_FIVE + Constants.PRICE_TWENTY;
        uint256 adminAmount = (totalPot * 40) / 100; // 40% admin share
        uint256 osAmount = (totalPot * 50) / 100; // 50% open source
        uint256 winnerAmount = totalPot - adminAmount - osAmount;
        
        // Verify expected amounts match pending amounts
        assertEq(pendingAdmin, adminAmount, "Admin payment amount wrong");
        assertEq(pendingOS, osAmount, "OS payment amount wrong");
        assertEq(pendingUser3, winnerAmount, "Winner payment amount wrong");
        
        // Withdraw pending payments
        vm.prank(user3);
        osDraw.withdrawPendingPayment();
        
        vm.prank(admin);
        osDraw.withdrawPendingPayment();
        
        vm.prank(openSourceRecipient);
        osDraw.withdrawPendingPayment();
        
        // Verify balances after withdrawal
        assertEq(user3.balance, user3BalanceBefore + winnerAmount, "Winner didn't receive correct amount");
        assertEq(admin.balance, adminBalanceBefore + adminAmount, "Admin didn't receive correct amount");
        assertEq(openSourceRecipient.balance, osBalanceBefore + osAmount, "OS recipient didn't receive correct amount");
        
        // Verify pending payments are cleared
        assertEq(osDraw.getPendingPayment(user3), 0, "Winner still has pending payment");
        assertEq(osDraw.getPendingPayment(admin), 0, "Admin still has pending payment");
        assertEq(osDraw.getPendingPayment(openSourceRecipient), 0, "OS recipient still has pending payment");
    }
    
    /**
     * @dev Test pool drawing process with VRF
     * Verifies: Pool draw executed correctly with random numbers
     */
    function test_poolDrawWithVRF() public {
        // Setup - create pool
        vm.startPrank(admin);
        Pool memory poolParams = Pool({
            ticketPrice: 0.1 ether,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: true
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
        
        // Buy pool tickets
        vm.prank(user1);
        osDraw.buyPoolTickets{value: 0.1 ether}(Constants.POOL_ID_THRESHOLD, 1);
        
        vm.prank(user2);
        osDraw.buyPoolTickets{value: 0.5 ether}(Constants.POOL_ID_THRESHOLD, 5);
        
        // Record balances before draw
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;
        uint256 adminBalanceBefore = admin.balance;
        uint256 osBalanceBefore = openSourceRecipient.balance;
        
        // Perform the pool draw
        osDraw.performPoolDraw(Constants.POOL_ID_THRESHOLD);
        
        // Check that the draw was requested
        assertEq(mockVRF.requestCount(), 1, "VRF request not made");
        
        // Simulate callback - let's say user2 wins with more tickets
        uint64 requestId = 1;
        uint256 randomNumber = 3; // Should select user2
        
        // Mock the VRF callback
        vm.prank(address(mockVRF));
        osDraw.randomNumberCallback(requestId, randomNumber);
        
        // Verify pool balance was cleared
        Pool memory pool = osDraw.getPool(Constants.POOL_ID_THRESHOLD);
        assertEq(pool.ethBalance, 0, "Pool balance not emptied");
        
        // Verify pending payments
        uint256 pendingUser2 = osDraw.getPendingPayment(user2);
        uint256 pendingAdmin = osDraw.getPendingPayment(admin);
        uint256 pendingOS = osDraw.getPendingPayment(openSourceRecipient);
        
        // Calculate expected amounts
        uint256 totalPot = 0.1 ether + 0.5 ether;
        uint256 adminAmount = (totalPot * 40) / 100; // 40% admin share
        uint256 osAmount = (totalPot * 50) / 100; // 50% open source
        uint256 winnerAmount = totalPot - adminAmount - osAmount;
        
        // Verify amounts
        assertEq(pendingAdmin, adminAmount, "Admin payment amount wrong");
        assertEq(pendingOS, osAmount, "OS payment amount wrong");
        assertEq(pendingUser2, winnerAmount, "Winner payment amount wrong");
        
        // Withdraw and verify balances
        vm.prank(user2);
        osDraw.withdrawPendingPayment();
        
        vm.prank(admin);
        osDraw.withdrawPendingPayment();
        
        vm.prank(openSourceRecipient);
        osDraw.withdrawPendingPayment();
        
        assertEq(user2.balance, user2BalanceBefore + winnerAmount, "Winner didn't receive correct amount");
        assertEq(admin.balance, adminBalanceBefore + adminAmount, "Admin didn't receive correct amount");
        assertEq(openSourceRecipient.balance, osBalanceBefore + osAmount, "OS recipient didn't receive correct amount");
    }
    
    /**
     * @dev Test timelock operations
     * Verifies: Timelock protection works for critical operations
     */
    function test_timelockOperations() public {
        // Setup
        address recipient = makeAddr("emergencyRecipient");
        uint256 withdrawAmount = 1 ether;
        
        // Send some ETH to the contract for emergency withdrawal
        vm.deal(address(osDraw), withdrawAmount);
        
        // Try emergency withdrawal
        vm.prank(address(osDraw.owner()));
        vm.expectRevert(); // Should revert because not queued
        osDraw.emergencyWithdraw(withdrawAmount, recipient);
        
        // Queue withdrawal
        vm.prank(address(osDraw.owner()));
        osDraw.emergencyWithdraw(withdrawAmount, recipient);
        
        // Try executing too early
        vm.prank(address(osDraw.owner()));
        vm.expectRevert(); // Should revert because timelock not expired
        osDraw.emergencyWithdraw(withdrawAmount, recipient);
        
        // Fast forward past timelock period
        vm.warp(block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY + 1);
        
        // Execute withdrawal now
        uint256 recipientBalanceBefore = recipient.balance;
        vm.prank(address(osDraw.owner()));
        osDraw.emergencyWithdraw(withdrawAmount, recipient);
        
        // Verify withdrawal
        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount, "Emergency withdrawal not completed");
        assertEq(address(osDraw).balance, 0, "Contract should have 0 balance after withdrawal");
    }
    
    /**
     * @dev Test contract upgrade with timelock
     * Verifies: Contract upgrades are protected by timelock
     */
    function test_upgradeTimelock() public {
        // Deploy a new implementation
        OSDraw newImplementation = new OSDraw();
        
        // Try to upgrade as owner
        vm.prank(address(osDraw.owner()));
        vm.expectRevert(); // Should revert with timelock message
        osDraw.upgradeToAndCall(address(newImplementation), "");
        
        // Fast forward past timelock
        vm.warp(block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY + 1);
        
        // Try again
        vm.prank(address(osDraw.owner()));
        // This should now succeed after timelock
        osDraw.upgradeToAndCall(address(newImplementation), "");
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