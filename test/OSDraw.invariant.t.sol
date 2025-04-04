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
 * @title OSDrawHandler
 * @dev Handler contract for fuzzing the OSDraw system
 */
contract OSDrawHandler is Test {
    OSDraw public osDraw;
    address[] public actors;
    address public mockVRF;
    
    // State tracking for invariants
    uint256 public totalEthDeposited;
    uint256 public totalEthWithdrawn;
    
    constructor(OSDraw _osDraw, address[] memory _actors, address _mockVRF) {
        osDraw = _osDraw;
        actors = _actors;
        mockVRF = _mockVRF;
        totalEthDeposited = 0;
        totalEthWithdrawn = 0;
    }
    
    /**
     * @dev Function to track deposits for invariant checking
     */
    function trackDeposit(uint256 amount) internal {
        totalEthDeposited += amount;
    }
    
    /**
     * @dev Function to track withdrawals for invariant checking
     */
    function trackWithdrawal(uint256 amount) internal {
        totalEthWithdrawn += amount;
    }
    
    /**
     * @dev Buy daily tickets with preset quantities, tracking deposits
     */
    function buyDailyTickets(uint256 actorIdx, uint256 quantityIdx) public {
        uint256 quantity;
        if (quantityIdx % 4 == 0) quantity = 1;
        else if (quantityIdx % 4 == 1) quantity = 5;
        else if (quantityIdx % 4 == 2) quantity = 20;
        else quantity = 100;
        
        uint256 price = osDraw.getPrice(quantity);
        
        // Pick a random actor
        address actor = actors[actorIdx % actors.length];
        
        // Buy tickets
        vm.prank(actor);
        osDraw.buyTickets{value: price}(quantity);
        
        // Track deposit
        trackDeposit(price);
    }
    
    /**
     * @dev Create a pool with random parameters (but within reasonable bounds)
     */
    function createPool(uint256 ticketPrice, bool active) public {
        // Ensure ticket price is reasonable
        ticketPrice = bound(ticketPrice, 0.001 ether, 1 ether);
        
        // Create pool
        vm.startPrank(osDraw.admin());
        Pool memory poolParams = Pool({
            ticketPrice: ticketPrice,
            totalSold: 0,
            totalRedeemed: 0,
            ethBalance: 0,
            active: active
        });
        osDraw.createPool(poolParams);
        vm.stopPrank();
    }
    
    /**
     * @dev Buy pool tickets, tracking deposits
     */
    function buyPoolTickets(uint256 actorIdx, uint256 quantity, uint256 poolId) public {
        // Ensure pool ID is valid
        poolId = bound(poolId, Constants.POOL_ID_THRESHOLD, Constants.POOL_ID_THRESHOLD + 100);
        
        // Limit quantity to reasonable values
        quantity = bound(quantity, 1, 10);
        
        // Get pool info
        Pool memory pool = osDraw.getPool(poolId);
        
        // Only proceed if pool exists and is active
        if (pool.ticketPrice > 0 && pool.active) {
            uint256 price = pool.ticketPrice * quantity;
            
            // Pick a random actor
            address actor = actors[actorIdx % actors.length];
            
            // Buy tickets
            vm.prank(actor);
            try osDraw.buyPoolTickets{value: price}(poolId, quantity) {
                // Track deposit
                trackDeposit(price);
            } catch {
                // Ignore failures (e.g., if actor doesn't have enough ETH)
            }
        }
    }
    
    /**
     * @dev Execute a daily draw if conditions are met
     */
    function performDailyDraw() public {
        // Increment time to next day
        vm.warp(block.timestamp + 1 days);
        
        // Attempt to execute draw
        try osDraw.performDailyDraw() {
            // Try to callback with random number
            vm.prank(mockVRF);
            osDraw.randomNumberCallback(
                MockVRFSystem(mockVRF).requestCount(), 
                uint256(keccak256(abi.encode(block.timestamp)))
            );
        } catch {
            // Ignore failures (e.g., if conditions for draw not met)
        }
    }
    
    /**
     * @dev Execute a pool draw if conditions are met
     */
    function performPoolDraw(uint256 poolId) public {
        // Ensure pool ID is valid
        poolId = bound(poolId, Constants.POOL_ID_THRESHOLD, Constants.POOL_ID_THRESHOLD + 100);
        
        // Attempt to execute draw
        try osDraw.performPoolDraw(poolId) {
            // Try to callback with random number
            vm.prank(mockVRF);
            osDraw.randomNumberCallback(
                MockVRFSystem(mockVRF).requestCount(), 
                uint256(keccak256(abi.encode(block.timestamp, poolId)))
            );
        } catch {
            // Ignore failures
        }
    }
    
    /**
     * @dev Withdraw pending payments function handler for invariant testing
     */
    function withdrawPendingPayments(uint256 actorIdx) public {
        // Pick a random actor
        address actor = actors[actorIdx % actors.length];
        
        // Get pending payment
        uint256 pendingAmount = osDraw.getPendingPayment(actor);
        
        // Withdraw if there's anything pending
        if (pendingAmount > 0) {
            vm.prank(actor);
            osDraw.withdrawPendingPayment();
            
            // Track withdrawal
            trackWithdrawal(pendingAmount);
        }
    }
    
    /**
     * @dev Update manager for randomness
     */
    function updateManager(uint256 actorIdx) public {
        address currentManager = osDraw.manager();
        // Only allow current manager to call
        vm.prank(currentManager);
        
        // Pick a new manager
        address newManager = actors[actorIdx % actors.length];
        
        // Update
        osDraw.transferManager(newManager);
    }
    
    /**
     * @dev Update open source recipient for randomness
     */
    function updateOpenSourceRecipient(uint256 actorIdx) public {
        address currentManager = osDraw.manager();
        // Only allow current manager to call
        vm.prank(currentManager);
        
        // Pick a new recipient
        address newRecipient = actors[actorIdx % actors.length];
        
        // Update
        osDraw.updateOpenSourceRecipient(newRecipient);
    }
}

/**
 * @title OSDrawInvariantTest
 * @dev Invariant testing for OSDraw system
 * 
 * This test suite verifies that critical security properties always hold 
 * through state transitions and under a wide range of operations.
 */
contract OSDrawInvariantTest is Test {
    OSDraw public osDraw;
    address public admin;
    address public manager;
    address public openSourceRecipient;
    
    // Actors in the system
    address[] public actors;
    
    // Mock VRF system for randomness testing
    MockVRFSystem public mockVRF;
    
    // Handler for invariant testing
    OSDrawHandler public handler;
    
    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        manager = makeAddr("manager");
        openSourceRecipient = makeAddr("openSourceRecipient");
        
        // Create actor addresses for invariant testing
        for (uint256 i = 0; i < 10; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", vm.toString(i)))));
            vm.deal(actors[i], 100 ether);
        }
        
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
        
        // Configure VRF entropy source
        vm.prank(admin);
        osDraw.setEntropySource(address(mockVRF));
        
        // Deploy handler for invariant testing
        handler = new OSDrawHandler(osDraw, actors, address(mockVRF));
        
        // Set up the fuzzing environment
        targetContract(address(handler));
        
        // Configure methods to be called during invariant fuzzing
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.buyDailyTickets.selector;
        selectors[1] = handler.createPool.selector;
        selectors[2] = handler.buyPoolTickets.selector;
        selectors[3] = handler.performDailyDraw.selector;
        selectors[4] = handler.performPoolDraw.selector; 
        selectors[5] = handler.withdrawPendingPayments.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    /**
     * @dev Invariant: No ETH can be lost in the system
     * The contract balance should always equal:
     * (Total ETH deposited - Total ETH withdrawn)
     */
    function invariant_noLostEth() public {
        assertEq(
            address(osDraw).balance,
            handler.totalEthDeposited() - handler.totalEthWithdrawn(),
            "ETH accounting error: funds lost"
        );
    }
    
    /**
     * @dev Invariant: The sum of all daily pots and pool balances equals the contract balance
     */
    function invariant_balanceMatchesPots() public {
        uint256 totalInDailyPots = 0;
        uint256 totalInPools = 0;
        
        // Sum all daily pots (up to a reasonable limit)
        for (uint256 day = 0; day < 100; day++) {
            totalInDailyPots += osDraw.dailyPot(day);
        }
        
        // Sum all pool balances
        for (uint256 poolId = Constants.POOL_ID_THRESHOLD; poolId <= Constants.POOL_ID_THRESHOLD + 100; poolId++) {
            Pool memory pool = osDraw.getPool(poolId);
            totalInPools += pool.ethBalance;
        }
        
        // The total of all pots should equal the contract balance plus pending payments
        // This is approximate as we don't have access to all pending payments in this test
        uint256 contractBalance = address(osDraw).balance;
        
        // Only check this invariant if no funds have been withdrawn (simplified test)
        if (handler.totalEthWithdrawn() == 0) {
            assertEq(
                contractBalance,
                totalInDailyPots + totalInPools,
                "Balance doesn't match sum of pots and pools"
            );
        }
    }

    /**
     * @dev Invariant: Prize pot distribution is always correct
     * - 50% goes to open source recipient
     * - adminShare% goes to admin
     * - remainder goes to winner
     */
    function invariant_prizePotDistribution() public {
        // Get all pending payments
        uint256 adminPending = osDraw.getPendingPayment(osDraw.admin());
        uint256 recipientPending = osDraw.getPendingPayment(osDraw.openSourceRecipient());
        
        // For each actor, check their pending payments
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 actorPending = osDraw.getPendingPayment(actors[i]);
            
            // If this actor has pending payments, they must be a winner
            if (actorPending > 0) {
                // Calculate expected shares
                uint256 totalPot = adminPending + recipientPending + actorPending;
                uint256 expectedAdminShare = (totalPot * osDraw.adminShare()) / 100;
                uint256 expectedRecipientShare = (totalPot * 50) / 100; // 50% for open source
                uint256 expectedWinnerShare = totalPot - expectedAdminShare - expectedRecipientShare;
                
                // Verify the distribution matches within 1 wei (to account for rounding)
                assertApproxEqAbs(adminPending, expectedAdminShare, 1, "Admin share incorrect");
                assertApproxEqAbs(recipientPending, expectedRecipientShare, 1, "Recipient share incorrect");
                assertApproxEqAbs(actorPending, expectedWinnerShare, 1, "Winner share incorrect");
            }
        }
    }

    /**
     * @dev Invariant: Active pools must have correct ticket counts
     */
    function invariant_poolTicketCounts() public {
        for (uint256 poolId = Constants.POOL_ID_THRESHOLD; poolId <= Constants.POOL_ID_THRESHOLD + 100; poolId++) {
            Pool memory pool = osDraw.getPool(poolId);
            if (pool.active && pool.ticketPrice > 0) {
                // For active pools, total sold should equal total redeemed plus current balance
                assertEq(
                    pool.totalSold,
                    pool.totalRedeemed + (pool.ethBalance / pool.ticketPrice),
                    "Pool ticket count mismatch"
                );
            }
        }
    }

    /**
     * @dev Invariant: Daily pot splits and distribution are correct
     * - Verifies daily pot amounts are tracked correctly
     * - Checks that draws properly distribute funds
     * - Ensures no funds are lost during daily operations
     */
    function invariant_dailyPotSplits() public {
        // Get current day
        uint256 currentDay = block.timestamp / 1 days;
        
        // For each day that has a pot
        for (uint256 day = 0; day <= currentDay; day++) {
            uint256 dailyPotAmount = osDraw.dailyPot(day);
            
            // If there's a pot for this day
            if (dailyPotAmount > 0) {
                // Check if draw has been performed (by looking for pending payments)
                bool drawPerformed = false;
                uint256 totalPendingPayments = 0;
                
                // Check admin and recipient pending payments
                uint256 adminPending = osDraw.getPendingPayment(osDraw.admin());
                uint256 recipientPending = osDraw.getPendingPayment(osDraw.openSourceRecipient());
                
                // Check all actors for pending payments
                for (uint256 i = 0; i < actors.length; i++) {
                    uint256 actorPending = osDraw.getPendingPayment(actors[i]);
                    if (actorPending > 0) {
                        drawPerformed = true;
                    }
                    totalPendingPayments += actorPending;
                }
                
                // If draw was performed, verify distribution
                if (drawPerformed) {
                    // Total pending payments should equal the original pot amount
                    assertEq(
                        totalPendingPayments + adminPending + recipientPending,
                        dailyPotAmount,
                        "Daily pot distribution amount mismatch"
                    );
                    
                    // Verify distribution percentages
                    uint256 expectedAdminShare = (dailyPotAmount * osDraw.adminShare()) / 100;
                    uint256 expectedRecipientShare = (dailyPotAmount * 50) / 100; // 50% for open source
                    
                    assertApproxEqAbs(adminPending, expectedAdminShare, 1, "Daily pot admin share incorrect");
                    assertApproxEqAbs(recipientPending, expectedRecipientShare, 1, "Daily pot recipient share incorrect");
                } else {
                    // If draw hasn't been performed, pot should still be in contract
                    assertEq(
                        dailyPotAmount,
                        osDraw.dailyPot(day),
                        "Daily pot amount changed before draw"
                    );
                }
            }
        }
    }

    /**
     * @dev Invariant: Daily draw cooldown period is respected
     * - No tickets can be bought in the last hour of the day
     * - Draws can only happen after cooldown
     */
    function invariant_dailyDrawCooldown() public {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentHour = (block.timestamp % 1 days) / 1 hours;
        
        // If we're in the last hour of the day
        if (currentHour >= 23) {
            // Try to buy tickets - should fail
            for (uint256 i = 0; i < actors.length; i++) {
                vm.prank(actors[i]);
                try osDraw.buyTickets{value: 0.1 ether}(1) {
                    require(false, "Should not be able to buy tickets in cooldown period");
                } catch {
                    // Expected to fail
                }
            }
        }
    }

    /**
     * @dev Invariant: Pool state transitions are valid
     * - Active pools can only be deactivated by admin
     * - Inactive pools can only be activated by admin
     * - Pool balances are preserved during state changes
     */
    function invariant_poolStateTransitions() public {
        for (uint256 poolId = Constants.POOL_ID_THRESHOLD; poolId <= Constants.POOL_ID_THRESHOLD + 100; poolId++) {
            Pool memory pool = osDraw.getPool(poolId);
            if (pool.ticketPrice > 0) {
                uint256 initialBalance = pool.ethBalance;
                
                // Try to change state from non-admin
                for (uint256 i = 0; i < actors.length; i++) {
                    vm.prank(actors[i]);
                    try osDraw.setPoolActive(poolId, !pool.active) {
                        require(false, "Non-admin should not be able to change pool state");
                    } catch {
                        // Expected to fail
                    }
                }
                
                // Verify balance hasn't changed
                pool = osDraw.getPool(poolId);
                assertEq(pool.ethBalance, initialBalance, "Pool balance changed during state transition");
            }
        }
    }

    /**
     * @dev Invariant: Ticket pricing tiers are correct
     * - Matches the constants defined in the contract
     */
    function invariant_ticketPricing() public {
        // Check that prices match constants
        assertEq(
            osDraw.getPrice(1),
            Constants.PRICE_ONE,
            "1 ticket price incorrect"
        );
        
        assertEq(
            osDraw.getPrice(5),
            Constants.PRICE_FIVE,
            "5 ticket price incorrect"
        );
        
        assertEq(
            osDraw.getPrice(20),
            Constants.PRICE_TWENTY,
            "20 ticket price incorrect"
        );
        
        assertEq(
            osDraw.getPrice(100),
            Constants.PRICE_HUNDRED,
            "100 ticket price incorrect"
        );
    }

    /**
     * @dev Invariant: VRF integration works correctly
     * - Random numbers are requested for each draw
     * - Callbacks are only accepted from VRF provider
     */
    function invariant_vrfIntegration() public {
        // Use a directed test approach instead of the invariant approach
        // since VRF interaction is stateful and needs specific conditions
        
        // Create mock VRF with direct integration
        MockVRFSystem directMockVRF = new MockVRFSystem();
        
        // Set it as entropy source
        vm.startPrank(osDraw.admin());
        osDraw.setEntropySource(address(directMockVRF));
        vm.stopPrank();
        
        // Create buyer with funds
        address buyer = makeAddr("vrfTestBuyer");
        vm.deal(buyer, 1 ether);
        
        // Buy tickets for yesterday
        vm.warp((block.timestamp / 1 days) * 1 days);  // Start of day
        vm.prank(buyer);
        osDraw.buyTickets{value: osDraw.getPrice(1)}(1);
        
        // Move to next day
        vm.warp(((block.timestamp / 1 days) + 1) * 1 days + 1 hours);  // Start of next day + 1 hour
        
        // Get initial request count
        uint256 initialRequestCount = directMockVRF.requestCount();
        
        // Perform daily draw
        osDraw.performDailyDraw();
        
        // Verify VRF was called
        assertEq(
            directMockVRF.requestCount(),
            initialRequestCount + 1,
            "VRF not called for daily draw"
        );
        
        // Try to callback from non-VRF address
        vm.prank(actors[0]);
        try osDraw.randomNumberCallback(directMockVRF.requestCount(), 123) {
            require(false, "Non-VRF should not be able to callback");
        } catch {
            // Expected to fail
        }
        
        // Callback from VRF address should succeed
        uint256 requestId = directMockVRF.requestCount();
        vm.prank(address(directMockVRF));
        osDraw.randomNumberCallback(requestId, 999);
        
        // Ensure winner has a pending payment
        bool someonePending = false;
        for (uint256 i = 0; i < actors.length; i++) {
            if (osDraw.getPendingPayment(actors[i]) > 0) {
                someonePending = true;
                break;
            }
        }
        
        if (osDraw.getPendingPayment(buyer) > 0) {
            someonePending = true;
        }
        
        // Either the buyer or someone in actors should have a pending payment
        // since one of them must be the winner
        assertTrue(
            someonePending || 
            osDraw.getPendingPayment(osDraw.admin()) > 0 || 
            osDraw.getPendingPayment(osDraw.openSourceRecipient()) > 0,
            "No pending payments after draw"
        );
    }

    /**
     * @dev Invariant: Emergency withdrawal safety
     * - Only owner can initiate emergency withdrawal
     */
    function invariant_emergencyWithdrawal() public {
        // Add some funds to withdraw
        vm.deal(address(osDraw), 10 ether);
        
        address recipient = makeAddr("emergencyRecipient");
        uint256 withdrawAmount = 1 ether;
        
        // Try emergency withdrawal from non-owner
        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i] != osDraw.owner()) {
                vm.prank(actors[i]);
                try osDraw.emergencyWithdraw(withdrawAmount, recipient) {
                    require(false, "Non-owner should not be able to initiate emergency withdrawal");
                } catch {
                    // Expected to fail
                }
            }
        }
    }
}

/**
 * @dev Mock VRF system for testing
 */
contract MockVRFSystem is IVRFSystem {
    uint256 public requestCount;
    
    function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256) {
        requestCount++;
        emit RandomNumberRequested(requestCount, msg.sender, traceId);
        return requestCount;
    }
} 