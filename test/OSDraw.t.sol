// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OSDraw.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OSDrawTest is Test {
    OSDraw public implementation;
    OSDraw public osdraw;
    address public openSourceRecipient;
    address public admin;
    address public manager;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;
    
    // Constants matching the contract
    uint256 constant ADMIN_SHARE = 5;
    uint256 constant PROJECT_SHARE = 50;
    uint256 constant PERCENT_DIVISOR = 100;
    uint256 constant PRICE_ONE = 0.01 ether;
    uint256 constant PRICE_FIVE = 0.048 ether;
    uint256 constant PRICE_TWENTY = 0.18 ether;
    uint256 constant PRICE_HUNDRED = 0.80 ether;

    function setUp() public {
        // Set up the addresses
        openSourceRecipient = makeAddr("openSourceRecipient");
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        user5 = makeAddr("user5");

        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(user4, 10 ether);
        vm.deal(user5, 10 ether);
        
        // Deploy implementation
        implementation = new OSDraw();
        
        // Create and initialize the proxy
        bytes memory initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            openSourceRecipient,
            admin,
            manager,
            ADMIN_SHARE
        );
        
        // Deploy with the test contract as the message sender (initializer)
        vm.prank(address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        osdraw = OSDraw(address(proxy));
    }
    
    // Test Init: Test that init parameters are correctly set
    function testInitialization() public view {
        assertEq(osdraw.openSourceRecipient(), openSourceRecipient, "Wrong open source recipient");
        assertEq(osdraw.admin(), admin, "Wrong admin");
        assertEq(osdraw.manager(), manager, "Wrong manager");
        assertEq(osdraw.adminShare(), ADMIN_SHARE, "Wrong admin share");
    }
    
    // Test 2: Initialize function can only be called once (proxy initialization)
    function testCannotReinitialize() public {
        vm.expectRevert();
        osdraw.initialize(openSourceRecipient, admin, manager, ADMIN_SHARE);
    }
    
    // Test 3: Initialize function validates addresses
    function testInitializeValidatesAddresses() public {
        OSDraw newImplementation = new OSDraw();
        
        // Test with zero address for openSourceRecipient
        vm.expectRevert("Invalid open source address");
        bytes memory initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            address(0),
            admin,
            manager,
            ADMIN_SHARE
        );
        new ERC1967Proxy(address(newImplementation), initData);
        
        // Test with zero address for admin
        vm.expectRevert("Invalid admin address");
        initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            openSourceRecipient,
            address(0),
            manager,
            ADMIN_SHARE
        );
        new ERC1967Proxy(address(newImplementation), initData);
        
        // Test with zero address for manager
        vm.expectRevert("Invalid manager address");
        initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            openSourceRecipient,
            admin,
            address(0),
            ADMIN_SHARE
        );
        new ERC1967Proxy(address(newImplementation), initData);
    }
    
    // Test 4: Initialize function validates share config
    function testInitializeValidatesShares() public {
        OSDraw newImplementation = new OSDraw();
        
        // Test with invalid share config (sum >= 100)
        uint256 invalidAdminShare = 51; // 51 + 50 > 100
        vm.expectRevert("Invalid share config");
        bytes memory initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            openSourceRecipient,
            admin,
            manager,
            invalidAdminShare
        );
        new ERC1967Proxy(address(newImplementation), initData);
    }
    
    // Test 5: Buying tickets function works correctly
    function testBuyTickets() public {
        // Simulate user1 buying 1 ticket
        vm.startPrank(user1);
        osdraw.buyTickets{value: PRICE_ONE}(1);
        vm.stopPrank();
        
        // Check the daily pot was updated
        uint256 day = getCurrentDay();
        assertEq(osdraw.dailyPot(day), PRICE_ONE, "Daily pot not updated correctly");
        
        // Verify the user's ticket was registered
        address[] memory tickets = osdraw.getTicketsByDay(day);
        assertEq(tickets.length, 1, "Wrong number of tickets");
        assertEq(tickets[0], user1, "Ticket not registered to the correct user");
    }
    
    // Test 6: Buying tickets with incorrect ETH amount
    function testBuyTicketsWithIncorrectAmount() public {
        vm.startPrank(user1);
        
        // Send wrong amount of ETH
        vm.expectRevert("Incorrect ETH sent");
        osdraw.buyTickets{value: 0.02 ether}(1);
        
        vm.stopPrank();
    }
    
    // Test 7: Buying tickets with invalid quantity
    function testBuyTicketsWithInvalidQuantity() public {
        vm.startPrank(user1);
        
        // Try to buy an invalid ticket quantity (2)
        vm.expectRevert("Invalid ticket quantity");
        osdraw.buyTickets{value: 0.02 ether}(2);
        
        vm.stopPrank();
    }
    
    // Test 8: Buying multiple tickets correctly
    function testBuyMultipleTickets() public {
        // User1 buys 5 tickets
        vm.startPrank(user1);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        vm.stopPrank();
        
        // User2 buys 20 tickets
        vm.startPrank(user2);
        osdraw.buyTickets{value: PRICE_TWENTY}(20);
        vm.stopPrank();
        
        uint256 day = getCurrentDay();
        
        // Verify daily pot is correct
        assertEq(osdraw.dailyPot(day), PRICE_FIVE + PRICE_TWENTY, "Daily pot incorrect");
        
        // Verify ticket counts
        address[] memory tickets = osdraw.getTicketsByDay(day);
        assertEq(tickets.length, 25, "Wrong number of tickets");
        
        // Check the first 5 tickets belong to user1
        for (uint i = 0; i < 5; i++) {
            assertEq(tickets[i], user1, "Wrong ticket owner");
        }
        
        // Check the next 20 tickets belong to user2
        for (uint i = 5; i < 25; i++) {
            assertEq(tickets[i], user2, "Wrong ticket owner");
        }
    }
    
    // Test 9: Performing a daily draw
    function testPerformDailyDraw() public {
        // User1 buys tickets on day 1
        uint256 day = getCurrentDay();
        vm.startPrank(user1);
        osdraw.buyTickets{value: PRICE_TWENTY}(20);
        vm.stopPrank();
        
        // Move to next day
        vm.warp(block.timestamp + 1 days);
        
        // Record balances before draw
        uint256 projectBalanceBefore = openSourceRecipient.balance;
        uint256 adminBalanceBefore = admin.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Perform the draw for the previous day
        osdraw.performDailyDraw();
        
        // Verify the draw was marked as executed
        assertTrue(osdraw.drawExecuted(day), "Draw not marked as executed");
        
        // Verify the pot was emptied
        assertEq(osdraw.dailyPot(day), 0, "Pot not emptied");
        
        // Calculate expected distribution
        uint256 totalPot = PRICE_TWENTY;
        uint256 projectShare = (totalPot * PROJECT_SHARE) / PERCENT_DIVISOR;
        uint256 adminShare = (totalPot * ADMIN_SHARE) / PERCENT_DIVISOR;
        uint256 winnerShare = totalPot - projectShare - adminShare;
        
        // Verify balances were updated correctly
        assertEq(openSourceRecipient.balance - projectBalanceBefore, projectShare, "Project didn't receive the correct share");
        assertEq(admin.balance - adminBalanceBefore, adminShare, "Admin didn't receive the correct share");
        
        // Since there's only one participant, user1 must be the winner
        assertEq(user1.balance - user1BalanceBefore, winnerShare, "Winner didn't receive the correct share");
    }
    
    // Test 10: Cannot perform draw twice
    function testCannotPerformDrawTwice() public {
        // User1 buys tickets on day 1
        uint256 day = getCurrentDay();
        vm.startPrank(user1);
        osdraw.buyTickets{value: PRICE_ONE}(1);
        vm.stopPrank();
        
        // Move to next day
        vm.warp(block.timestamp + 1 days);
        
        // Perform the draw
        osdraw.performDailyDraw();
        
        // Try to perform the draw again
        vm.expectRevert("Draw already performed");
        osdraw.performDailyDraw();
    }
    
    // Test 11: Cannot perform draw if no tickets were purchased
    function testCannotPerformDrawWithNoTickets() public {
        // Move to the next day without purchasing any tickets
        vm.warp(block.timestamp + 1 days);
        
        // Try to perform the draw
        vm.expectRevert("No tickets for draw day");
        osdraw.performDailyDraw();
    }
    
    // Test 12: Updating the open source recipient
    function testUpdateOpenSourceRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        
        // Only manager can update
        vm.prank(manager);
        osdraw.updateOpenSourceRecipient(newRecipient);
        
        assertEq(osdraw.openSourceRecipient(), newRecipient, "Recipient not updated");
    }
    
    // Test 13: Non-manager cannot update recipient
    function testNonManagerCannotUpdateRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        
        // Try to update as non-manager
        vm.startPrank(user1);
        vm.expectRevert("Only manager can call this function");
        osdraw.updateOpenSourceRecipient(newRecipient);
        vm.stopPrank();
    }
    
    // Test 14: Cannot update recipient to zero address
    function testCannotUpdateRecipientToZeroAddress() public {
        vm.startPrank(manager);
        vm.expectRevert("Invalid recipient");
        osdraw.updateOpenSourceRecipient(address(0));
        vm.stopPrank();
    }
    
    // Test 15: Transferring the manager role
    function testTransferManager() public {
        address newManager = makeAddr("newManager");
        
        vm.startPrank(manager);
        osdraw.transferManager(newManager);
        vm.stopPrank();
        
        assertEq(osdraw.manager(), newManager, "Manager not transferred");
    }
    
    // Test 16: Non-manager cannot transfer manager role
    function testNonManagerCannotTransferRole() public {
        address newManager = makeAddr("newManager");
        
        vm.startPrank(user1);
        vm.expectRevert("Only manager can call this function");
        osdraw.transferManager(newManager);
        vm.stopPrank();
    }
    
    // Test 17: Cannot transfer manager role to zero address
    function testCannotTransferManagerToZeroAddress() public {
        vm.startPrank(manager);
        vm.expectRevert("Invalid manager");
        osdraw.transferManager(address(0));
        vm.stopPrank();
    }
    
    // Test 18: Testing ticket prices
    function testTicketPrices() public {
        assertEq(osdraw.getPrice(1), PRICE_ONE, "Wrong price for 1 ticket");
        assertEq(osdraw.getPrice(5), PRICE_FIVE, "Wrong price for 5 tickets");
        assertEq(osdraw.getPrice(20), PRICE_TWENTY, "Wrong price for 20 tickets");
        assertEq(osdraw.getPrice(100), PRICE_HUNDRED, "Wrong price for 100 tickets");
        
        // Test invalid quantities
        vm.expectRevert("Invalid ticket quantity");
        osdraw.getPrice(2);
        
        vm.expectRevert("Invalid ticket quantity");
        osdraw.getPrice(0);
        
        vm.expectRevert("Invalid ticket quantity");
        osdraw.getPrice(101);
    }
    
    // Test 19: Test upgrade authentication
    function testUpgradeAuth() public {
        OSDraw newImplementation = new OSDraw();
        
        // Print owner information for debugging
        address owner = osdraw.owner();
        console.log("Owner address:", owner);
        console.log("Test contract address:", address(this));
        
        // Non-owner cannot upgrade
        vm.startPrank(user1);
        // Use expectRevert with bytes4 selector for OwnableUnauthorizedAccount
        vm.expectRevert(
            abi.encodeWithSelector(
                0x118cdaa7, // OwnableUnauthorizedAccount error selector
                user1
            )
        );
        osdraw.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
        
        // Owner can upgrade
        vm.prank(owner); // Use the actual owner
        osdraw.upgradeToAndCall(address(newImplementation), "");
    }
    
    // Test: Multiple users buy tickets in multiple rounds
    function testMultipleRoundTicketPurchase() public {
        uint256 day = getCurrentDay();
        
        // First round: All users buy tickets
        vm.prank(user1);
        osdraw.buyTickets{value: PRICE_ONE}(1);
        
        vm.prank(user2);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        
        vm.prank(user3);
        osdraw.buyTickets{value: PRICE_ONE}(1);
        
        vm.prank(user4);
        osdraw.buyTickets{value: PRICE_TWENTY}(20);
        
        vm.prank(user5);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        
        // Second round: users 1 and 3 buy more tickets
        vm.prank(user1);
        osdraw.buyTickets{value: PRICE_TWENTY}(20);
        
        vm.prank(user3);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        
        // Verify total pot for the current day
        uint256 expectedPot = PRICE_ONE + PRICE_FIVE + PRICE_ONE + PRICE_TWENTY + PRICE_FIVE + PRICE_TWENTY + PRICE_FIVE;
        assertEq(osdraw.dailyPot(day), expectedPot, "Daily pot incorrect");
        
        // Verify total tickets
        address[] memory tickets = osdraw.getTicketsByDay(day);
        assertEq(tickets.length, 1 + 5 + 1 + 20 + 5 + 20 + 5, "Wrong number of tickets");
        
        // Verify ticket ownership pattern
        // First round tickets
        assertEq(tickets[0], user1, "Wrong owner for ticket 0");
        
        for (uint i = 1; i < 6; i++) {
            assertEq(tickets[i], user2, "Wrong owner in user2 first batch");
        }
        
        assertEq(tickets[6], user3, "Wrong owner for ticket 6");
        
        for (uint i = 7; i < 27; i++) {
            assertEq(tickets[i], user4, "Wrong owner in user4 batch");
        }
        
        for (uint i = 27; i < 32; i++) {
            assertEq(tickets[i], user5, "Wrong owner in user5 batch");
        }
        
        // Second round tickets - user1's additional tickets
        for (uint i = 32; i < 52; i++) {
            assertEq(tickets[i], user1, "Wrong owner in user1 second batch");
        }
        
        // Second round tickets - user3's additional tickets
        for (uint i = 52; i < 57; i++) {
            assertEq(tickets[i], user3, "Wrong owner in user3 second batch");
        }
    }
    
    // Test for getUserTicketCount function
    function testGetUserTicketCount() public {
        uint256 day = getCurrentDay();
        
        // No tickets initially
        assertEq(osdraw.getUserTicketCount(user1, day), 0, "Should have 0 tickets initially");
        
        // User1 buys 1 ticket
        vm.prank(user1);
        osdraw.buyTickets{value: PRICE_ONE}(1);
        assertEq(osdraw.getUserTicketCount(user1, day), 1, "Should have 1 ticket after first purchase");
        
        // User2 buys 5 tickets
        vm.prank(user2);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        assertEq(osdraw.getUserTicketCount(user2, day), 5, "Should have 5 tickets");
        
        // User1 buys 20 more tickets
        vm.prank(user1);
        osdraw.buyTickets{value: PRICE_TWENTY}(20);
        assertEq(osdraw.getUserTicketCount(user1, day), 21, "Should have 21 tickets after second purchase");
        
        // User3 buys no tickets
        assertEq(osdraw.getUserTicketCount(user3, day), 0, "Should have 0 tickets if none purchased");
        
        // Check for a different day
        uint256 nextDay = day + 1;
        assertEq(osdraw.getUserTicketCount(user1, nextDay), 0, "Should have 0 tickets on a different day");
        
        // User1 buys tickets on next day
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        osdraw.buyTickets{value: PRICE_FIVE}(5);
        
        // Check that tickets are tracked correctly across days
        assertEq(osdraw.getUserTicketCount(user1, day), 21, "Should still have 21 tickets for first day");
        assertEq(osdraw.getUserTicketCount(user1, nextDay), 5, "Should have 5 tickets for second day");
    }
    
    // Helper function to get the current day
    function getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
} 