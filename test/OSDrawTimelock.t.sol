// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {OSDraw} from "../src/OSDraw.sol";
import {OSDrawTimelock} from "../src/timelock/OSDrawTimelock.sol";
import {Constants} from "../src/model/Constants.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OSDrawTimelockTest
 * @dev Test suite for the OSDrawTimelock implementation
 */
contract OSDrawTimelockTest is Test {
    OSDrawTimelock public timelock;
    OSDraw public osDraw;
    address public admin;
    address public proposer;
    address public executor;
    address public user;
    
    // Roles
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    function setUp() public {
        admin = makeAddr("admin");
        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        user = makeAddr("user");
        
        // Set up proposers and executors arrays
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        
        address[] memory executors = new address[](1);
        executors[0] = executor;
        
        // Deploy timelock with 2-day delay
        timelock = new OSDrawTimelock(
            Constants.DEFAULT_TIMELOCK_DELAY,
            proposers,
            executors,
            admin
        );
        
        // Deploy OSDraw implementation
        OSDraw implementation = new OSDraw();
        
        // Deploy proxy pointing to implementation with timelock as owner
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                OSDraw.initialize.selector,
                makeAddr("openSourceRecipient"),
                admin,
                makeAddr("manager"),
                40 // Admin share of 40%
            )
        );
        
        // Cast proxy to OSDraw interface
        osDraw = OSDraw(address(proxy));
        
        // Transfer ownership to timelock
        vm.prank(osDraw.owner());
        osDraw.transferOwnership(address(timelock));
    }

    /**
     * @dev Test that roles are set correctly
     */
    function test_roles() public view {
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, executor));
        assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
    }
    
    /**
     * @dev Test scheduling and executing an operation
     */
    function test_scheduleAndExecute() public {
        // Create data for upgrading OSDraw
        address newImplementation = address(new OSDraw());
        bytes memory data = abi.encodeWithSelector(osDraw.upgradeToAndCall.selector, newImplementation, "");
        
        // Schedule the proposal
        vm.prank(proposer);
        bytes32 operationId = timelock.hashOperation(
            address(osDraw),
            0,
            data,
            bytes32(0),
            bytes32(0)
        );
        
        vm.prank(proposer);
        timelock.schedule(
            address(osDraw),
            0,
            data,
            bytes32(0),
            bytes32(0),
            Constants.DEFAULT_TIMELOCK_DELAY
        );
        
        // Verify operation is scheduled
        assertTrue(timelock.isOperationPending(operationId));
        assertFalse(timelock.isOperationReady(operationId));
        
        // Fast forward past timelock period
        vm.warp(block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY + 1);
        
        // Verify operation is ready
        assertTrue(timelock.isOperationReady(operationId));
        
        // Execute the operation
        vm.prank(executor);
        timelock.execute(
            address(osDraw),
            0,
            data,
            bytes32(0),
            bytes32(0)
        );
        
        // Verify operation is done
        assertTrue(timelock.isOperationDone(operationId));
        
        // Verify implementation was updated
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 implAddress = vm.load(address(osDraw), implSlot);
        assertEq(address(uint160(uint256(implAddress))), newImplementation, "Implementation not updated");
    }
    
    /**
     * @dev Test operation cancellation
     */
    function test_cancelOperation() public {
        // Create data for upgrading OSDraw
        address newImplementation = address(new OSDraw());
        bytes memory data = abi.encodeWithSelector(osDraw.upgradeToAndCall.selector, newImplementation, "");
        
        // Schedule the proposal
        vm.prank(proposer);
        bytes32 operationId = timelock.hashOperation(
            address(osDraw),
            0,
            data,
            bytes32(0),
            bytes32(0)
        );
        
        vm.prank(proposer);
        timelock.schedule(
            address(osDraw),
            0,
            data,
            bytes32(0),
            bytes32(0),
            Constants.DEFAULT_TIMELOCK_DELAY
        );
        
        // Verify operation is scheduled
        assertTrue(timelock.isOperationPending(operationId));
        
        // Cancel the operation
        vm.prank(proposer);
        timelock.cancel(operationId);
        
        // Verify operation is cancelled
        assertFalse(timelock.isOperationPending(operationId));
    }
    
    /**
     * @dev Test operation batch scheduling and execution
     */
    function test_batchOperations() public {
        // Create multiple operations
        address[] memory targets = new address[](2);
        targets[0] = address(osDraw);
        targets[1] = address(osDraw);
        
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        
        bytes[] memory payloads = new bytes[](2);
        
        // Create operation 1: Set a new implementation for upgrade
        address newImplementation = address(new OSDraw());
        payloads[0] = abi.encodeWithSelector(osDraw.upgradeToAndCall.selector, newImplementation, "");
        
        // Create operation 2: Transfer ownership to admin (only owner can do this)
        payloads[1] = abi.encodeWithSelector(osDraw.transferOwnership.selector, admin);
        
        // Schedule the batch
        vm.prank(proposer);
        bytes32 operationId = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            bytes32(0),
            bytes32(0)
        );
        
        vm.prank(proposer);
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            bytes32(0),
            bytes32(0),
            Constants.DEFAULT_TIMELOCK_DELAY
        );
        
        // Verify batch is scheduled
        assertTrue(timelock.isOperationPending(operationId));
        
        // Fast forward past timelock period
        vm.warp(block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY + 1);
        
        // Execute the batch
        vm.prank(executor);
        timelock.executeBatch(
            targets,
            values,
            payloads,
            bytes32(0),
            bytes32(0)
        );
        
        // Verify operation is done
        assertTrue(timelock.isOperationDone(operationId));
        
        // Verify changes were made
        // 1. Verify implementation was updated
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 implAddress = vm.load(address(osDraw), implSlot);
        assertEq(address(uint160(uint256(implAddress))), newImplementation, "Implementation not updated");
        
        // 2. Verify ownership was transferred
        assertEq(osDraw.owner(), admin, "Ownership not transferred to admin");
    }
} 