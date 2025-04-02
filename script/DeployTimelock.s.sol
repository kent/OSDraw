// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/timelock/OSDrawTimelock.sol";
import "../src/OSDraw.sol";
import "../src/model/Constants.sol";

/**
 * @title DeployTimelock
 * @dev Script to deploy the OSDrawTimelock and set it as the owner of OSDraw
 * 
 * To run:
 * forge script script/DeployTimelock.s.sol:DeployTimelock --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployTimelock is Script {
    function run() public {
        // Address of the existing OSDraw proxy
        address osDrawProxy = vm.envAddress("OSDRAW_PROXY");
        
        // Addresses for timelock roles
        address proposer = vm.envAddress("PROPOSER");
        address executor = vm.envAddress("EXECUTOR");
        address admin = vm.envAddress("ADMIN");
        
        // Set up proposers array
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        
        // Set up executors array
        address[] memory executors = new address[](1);
        executors[0] = executor;
        
        // Start broadcast (authenticated transaction)
        vm.startBroadcast();
        
        // Deploy timelock with default delay from Constants
        OSDrawTimelock timelock = new OSDrawTimelock(
            Constants.DEFAULT_TIMELOCK_DELAY,
            proposers,
            executors,
            admin
        );
        
        // Transfer ownership of OSDraw to the timelock
        OSDraw osDraw = OSDraw(payable(osDrawProxy));
        osDraw.transferOwnership(address(timelock));
        
        vm.stopBroadcast();
        
        // Log the addresses
        console.log("OSDrawTimelock deployed at:", address(timelock));
        console.log("OSDraw ownership transferred to timelock");
        console.log("Proposer:", proposer);
        console.log("Executor:", executor);
        console.log("Admin:", admin);
    }
} 