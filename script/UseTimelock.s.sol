// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/timelock/OSDrawTimelock.sol";
import "../src/OSDraw.sol";
import "../src/model/Constants.sol";

/**
 * @title UseTimelock
 * @dev Script demonstrating how to use the OSDrawTimelock
 * 
 * To schedule an operation:
 * forge script script/UseTimelock.s.sol:ScheduleOperation --rpc-url $RPC_URL --private-key $PROPOSER_KEY --broadcast
 * 
 * To execute an operation:
 * forge script script/UseTimelock.s.sol:ExecuteOperation --rpc-url $RPC_URL --private-key $EXECUTOR_KEY --broadcast
 */

/**
 * @dev Base script with common functionality
 */
contract TimelockScript is Script {
    // Common variables
    OSDrawTimelock timelock;
    OSDraw osDraw;
    
    // Operation details
    address target;
    uint256 value;
    bytes data;
    bytes32 predecessor;
    bytes32 salt;
    
    function setUp() public virtual {
        // Get addresses from environment
        address timelockAddress = vm.envAddress("TIMELOCK_ADDRESS");
        address osDrawAddress = vm.envAddress("OSDRAW_PROXY");
        
        // Initialize contracts
        timelock = OSDrawTimelock(payable(timelockAddress));
        osDraw = OSDraw(payable(osDrawAddress));
    }
    
    function getOperationId() public view returns (bytes32) {
        return timelock.hashOperation(target, value, data, predecessor, salt);
    }
}

/**
 * @dev Script to schedule an operation using the timelock
 */
contract ScheduleOperation is TimelockScript {
    function setUp() public override {
        super.setUp();
        
        // Set operation details for updating open source recipient
        target = address(osDraw);
        value = 0;
        address newRecipient = vm.envAddress("NEW_RECIPIENT");
        data = abi.encodeWithSelector(osDraw.updateOpenSourceRecipient.selector, newRecipient);
        predecessor = bytes32(0);
        salt = keccak256(abi.encodePacked("update-recipient", block.timestamp));
    }
    
    function run() public {
        // Start broadcast (authenticated transaction)
        vm.startBroadcast();
        
        // Schedule the operation
        timelock.schedule(
            target,
            value,
            data,
            predecessor,
            salt,
            Constants.DEFAULT_TIMELOCK_DELAY
        );
        
        vm.stopBroadcast();
        
        // Log the operation details
        bytes32 operationId = getOperationId();
        console.log("Operation scheduled:");
        console.logBytes32(operationId);
        console.log("Will be ready after:", block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY);
    }
}

/**
 * @dev Script to execute a scheduled operation
 */
contract ExecuteOperation is TimelockScript {
    function setUp() public override {
        super.setUp();
        
        // Get operation details from environment variables
        target = vm.envAddress("TARGET");
        value = vm.envUint("VALUE");
        data = vm.envBytes("DATA");
        predecessor = vm.envBytes32("PREDECESSOR");
        salt = vm.envBytes32("SALT");
    }
    
    function run() public {
        bytes32 operationId = getOperationId();
        
        // Check if operation is ready
        require(timelock.isOperationReady(operationId), "Operation not ready");
        
        // Start broadcast (authenticated transaction)
        vm.startBroadcast();
        
        // Execute the operation
        timelock.execute(
            target,
            value,
            data,
            predecessor,
            salt
        );
        
        vm.stopBroadcast();
        
        // Log the execution
        console.log("Operation executed:");
        console.logBytes32(operationId);
    }
}

/**
 * @dev Script to schedule a batch operation
 */
contract ScheduleBatchOperation is TimelockScript {
    function run() public {
        // Example batch operation: update recipient and transfer manager
        address[] memory targets = new address[](2);
        targets[0] = address(osDraw);
        targets[1] = address(osDraw);
        
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        
        address newRecipient = vm.envAddress("NEW_RECIPIENT");
        address newManager = vm.envAddress("NEW_MANAGER");
        
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSelector(osDraw.updateOpenSourceRecipient.selector, newRecipient);
        payloads[1] = abi.encodeWithSelector(osDraw.transferManager.selector, newManager);
        
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(abi.encodePacked("batch-update", block.timestamp));
        
        // Start broadcast
        vm.startBroadcast();
        
        // Schedule batch
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt,
            Constants.DEFAULT_TIMELOCK_DELAY
        );
        
        vm.stopBroadcast();
        
        // Log the batch operation ID
        bytes32 operationId = timelock.hashOperationBatch(targets, values, payloads, predecessor, salt);
        console.log("Batch operation scheduled:");
        console.logBytes32(operationId);
        console.log("Will be ready after:", block.timestamp + Constants.DEFAULT_TIMELOCK_DELAY);
    }
} 