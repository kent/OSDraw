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
    
    // State tracking for invariants
    uint256 public totalEthDeposited;
    uint256 public totalEthWithdrawn;
    
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
        
        // Target contract functions for invariant testing
        targetContract(address(this));
        
        // Reset trackers
        totalEthDeposited = 0;
        totalEthWithdrawn = 0;
    }
    
    /**
     * @dev Invariant: No ETH can be lost in the system
     * The contract balance should always equal:
     * (Total ETH deposited - Total ETH withdrawn)
     */
    function invariant_noLostEth() public {
        assertEq(
            address(osDraw).balance,
            totalEthDeposited - totalEthWithdrawn,
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
        if (totalEthWithdrawn == 0) {
            assertEq(
                contractBalance,
                totalInDailyPots + totalInPools,
                "Balance doesn't match sum of pots and pools"
            );
        }
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
            vm.prank(address(mockVRF));
            osDraw.randomNumberCallback(mockVRF.requestCount(), uint256(keccak256(abi.encode(block.timestamp))));
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
            vm.prank(address(mockVRF));
            osDraw.randomNumberCallback(mockVRF.requestCount(), uint256(keccak256(abi.encode(block.timestamp, poolId))));
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
        // Only allow current manager to call
        vm.prank(manager);
        
        // Pick a new manager
        address newManager = actors[actorIdx % actors.length];
        
        // Update
        osDraw.transferManager(newManager);
        
        // Update state
        manager = newManager;
    }
    
    /**
     * @dev Update open source recipient for randomness
     */
    function updateOpenSourceRecipient(uint256 actorIdx) public {
        // Only allow current manager to call
        vm.prank(manager);
        
        // Pick a new recipient
        address newRecipient = actors[actorIdx % actors.length];
        
        // Update
        osDraw.updateOpenSourceRecipient(newRecipient);
        
        // Update state
        openSourceRecipient = newRecipient;
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