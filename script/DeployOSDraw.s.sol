// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OSDraw Deployment Script
 * @dev This script handles the complete deployment process for the OSDraw contract system
 *      including setup of proxy contracts and initialization of the system with
 *      proper configuration values.
 */

import "forge-std/Script.sol";
import "../src/OSDraw.sol";
import "../src/model/Pool.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployOSDraw is Script {
    /**
     * @dev Execution function that runs when the script is executed
     * This function:
     *  1. Sets up variables for deployment
     *  2. Deploys the implementation contract
     *  3. Creates and initializes a proxy pointing to the implementation
     *  4. Creates an initial pool in the system
     *  5. Logs the deployment addresses
     */
    function run() external {
        // Load the private key for deployment from environment or .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Deployment addresses - these should be set to the appropriate values for your deployment
        address openSourceRecipient = vm.envAddress("OPENSOURCE_RECIPIENT");
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address managerAddress = vm.envAddress("MANAGER_ADDRESS");
        
        // Configuration parameters - adjust as needed
        uint256 adminShare = 5; // 5% of the pot goes to admin
        
        // Begin deployment with the deployer's private key
        vm.startBroadcast(deployerPrivateKey);
        
        // -------------------------------------------------------------------------
        // Step 1: Deploy the implementation contract
        // -------------------------------------------------------------------------
        // First, we deploy the implementation contract that contains all logic
        // This contract should not be directly used by users
        console.log("Deploying implementation contract...");
        OSDraw implementation = new OSDraw();
        console.log("Implementation deployed at:", address(implementation));
        
        // -------------------------------------------------------------------------
        // Step 2: Encode initialization data for the proxy
        // -------------------------------------------------------------------------
        // The initialization data is encoded to be passed to the proxy constructor
        // This data will be used to initialize the contract state
        bytes memory initData = abi.encodeWithSelector(
            OSDraw.initialize.selector,
            openSourceRecipient, // OpenSource project that receives a share
            adminAddress,        // Admin who can manage the system
            managerAddress,      // Manager who can update configurations
            adminShare           // Admin's share of the pot (percentage)
        );
        console.log("Initialization data encoded");
        
        // -------------------------------------------------------------------------
        // Step 3: Deploy the proxy contract
        // -------------------------------------------------------------------------
        // The proxy delegates all calls to the implementation while maintaining its own storage
        // This allows us to upgrade the implementation later without losing state
        console.log("Deploying proxy contract...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), // The implementation to delegate to
            initData                 // The initialization data
        );
        console.log("Proxy deployed at:", address(proxy));
        
        // -------------------------------------------------------------------------
        // Step 4: Create a wrapper for easier interaction with the proxy
        // -------------------------------------------------------------------------
        // We create a wrapper around the proxy to interact with it using the OSDraw interface
        OSDraw osdraw = OSDraw(address(proxy));
        console.log("Proxy wrapped as OSDraw at:", address(osdraw));
        
        // -------------------------------------------------------------------------
        // Step 5: Create the first pool
        // -------------------------------------------------------------------------
        // Create a Pool struct with the initial configuration
        Pool memory initialPool = Pool({
            ticketPrice: 0.01 ether,  // Each ticket costs 0.01 ETH
            totalSold: 0,             // No tickets sold yet
            totalRedeemed: 0,         // No tickets redeemed yet
            ethBalance: 0,            // No initial balance
            active: true              // The pool is active immediately
        });
        
        // Create the pool in the contract
        console.log("Creating initial pool...");
        osdraw.createPool(initialPool);
        console.log("Initial pool created with ID: 1");
        
        // -------------------------------------------------------------------------
        // Step 6: Add initial liquidity to the pool (optional)
        // -------------------------------------------------------------------------
        // You may want to add some initial liquidity to the pool
        // This is especially important for the first pool to have prizes available
        console.log("Adding initial liquidity to the pool...");
        osdraw.addLiquidity{value: 1 ether}(1); // Add 1 ETH to pool ID 1
        console.log("Added 1 ETH as initial liquidity");
        
        // -------------------------------------------------------------------------
        // Step 7: Set up VRF integration (if available)
        // -------------------------------------------------------------------------
        // If you have a VRF provider address, set it up
        address vrfProvider = vm.envOr("VRF_PROVIDER_ADDRESS", address(0));
        if (vrfProvider != address(0)) {
            console.log("Setting up VRF integration...");
            osdraw.setEntropySource(vrfProvider);
            console.log("VRF provider set to:", vrfProvider);
        } else {
            console.log("No VRF provider specified. Random draws will not work until a provider is set.");
        }
        
        // End the broadcast - this is important to signal the end of the transaction group
        vm.stopBroadcast();
        
        // -------------------------------------------------------------------------
        // Step 8: Output Summary of Deployment
        // -------------------------------------------------------------------------
        console.log("\n=== OSDraw Deployment Summary ===");
        console.log("Implementation: ", address(implementation));
        console.log("Proxy:          ", address(proxy));
        console.log("OpenSource:     ", openSourceRecipient);
        console.log("Admin:          ", adminAddress);
        console.log("Manager:        ", managerAddress);
        console.log("Admin Share:    ", adminShare, "%");
        console.log("Initial Pool ID: 1");
        console.log("Version:        ", osdraw.getVersion());
        console.log("VRF Provider:   ", vrfProvider == address(0) ? "Not configured" : vm.toString(vrfProvider));
        console.log("================================\n");
        
        console.log("Deployment completed successfully!");
    }
}

/**
 * @title OSDraw Upgrade Script
 * @dev This script handles upgrading the OSDraw contract to a new implementation
 *      This script would be used after deploying a new implementation contract.
 */
contract UpgradeOSDraw is Script {
    /**
     * @dev Execution function that runs when the script is executed
     * This function:
     *  1. Deploys a new implementation contract
     *  2. Upgrades the existing proxy to point to the new implementation
     */
    function run() external {
        // Load the private key for deployment from environment or .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Load the address of the existing proxy contract from environment
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        
        // Begin the upgrade process
        vm.startBroadcast(deployerPrivateKey);
        
        // -------------------------------------------------------------------------
        // Step 1: Deploy the new implementation contract
        // -------------------------------------------------------------------------
        console.log("Deploying new implementation contract...");
        OSDraw newImplementation = new OSDraw();
        console.log("New implementation deployed at:", address(newImplementation));
        
        // -------------------------------------------------------------------------
        // Step 2: Create a wrapper for the existing proxy
        // -------------------------------------------------------------------------
        OSDraw osdraw = OSDraw(proxyAddress);
        console.log("Existing proxy wrapped at:", address(osdraw));
        
        // -------------------------------------------------------------------------
        // Step 3: Upgrade the proxy to the new implementation
        // -------------------------------------------------------------------------
        // Note: This requires that the deployer is the owner of the proxy
        // OSDraw uses the UUPS upgrade pattern, so upgrades are done via the proxy itself
        console.log("Upgrading proxy to new implementation...");
        
        // The first upgrade attempt will be queued due to timelock
        try osdraw.upgradeToAndCall(address(newImplementation), "") {
            console.log("Upgrade succeeded without timelock - unexpected behavior");
        } catch Error(string memory reason) {
            console.log("Upgrade queued as expected: ", reason);
            console.log("You'll need to run this script again after the timelock period expires");
            
            // Stop broadcast since we need to wait for timelock
            vm.stopBroadcast();
            return;
        }
        
        // If the upgrade proceeded without timelock, verify it
        console.log("Proxy upgraded to:", address(newImplementation));
        
        // -------------------------------------------------------------------------
        // Step 4: Verify the upgrade was successful
        // -------------------------------------------------------------------------
        uint256 newVersion = osdraw.getVersion();
        console.log("New contract version:", newVersion);
        
        // End the broadcast
        vm.stopBroadcast();
        
        // -------------------------------------------------------------------------
        // Step 5: Output Summary of Upgrade
        // -------------------------------------------------------------------------
        console.log("\n=== OSDraw Upgrade Summary ===");
        console.log("Proxy:                   ", proxyAddress);
        console.log("New Implementation:      ", address(newImplementation));
        console.log("New Version:             ", newVersion);
        console.log("==============================\n");
        
        console.log("Upgrade completed successfully!");
    }
}

/**
 * 
 * DEPLOYMENT INSTRUCTIONS
 * 
 * Prerequisites:
 * 1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
 * 2. Clone the repository
 * 3. Install dependencies: `forge install`
 * 4. Create a .env file with the required environment variables:
 *    ```
 *    PRIVATE_KEY=your_private_key_here
 *    OPENSOURCE_RECIPIENT=0x...
 *    ADMIN_ADDRESS=0x...
 *    MANAGER_ADDRESS=0x...
 *    VRF_PROVIDER_ADDRESS=0x... (optional)
 *    ```
 * 
 * Deployment Steps:
 * 1. Compile the contracts: `forge build`
 * 2. Run the deployment script:
 *    For testnet:
 *    ```
 *    source .env
 *    forge script script/DeployOSDraw.s.sol:DeployOSDraw --rpc-url https://rpc-url-for-your-testnet --broadcast --verify
 *    ```
 *    For mainnet:
 *    ```
 *    source .env
 *    forge script script/DeployOSDraw.s.sol:DeployOSDraw --rpc-url https://rpc-url-for-mainnet --broadcast --verify
 *    ```
 * 
 * Verification:
 * After deployment, verify the proxy and implementation contracts on Etherscan:
 * ```
 * forge verify-contract <IMPLEMENTATION_ADDRESS> src/OSDraw.sol:OSDraw --chain-id <CHAIN_ID> --etherscan-api-key <YOUR_API_KEY>
 * forge verify-contract <PROXY_ADDRESS> @openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --chain-id <CHAIN_ID> --etherscan-api-key <YOUR_API_KEY>
 * ```
 * 
 * Future Upgrades:
 * To upgrade the contract in the future, update the `PROXY_ADDRESS` in your .env file and run:
 * ```
 * source .env
 * forge script script/DeployOSDraw.s.sol:UpgradeOSDraw --rpc-url <RPC_URL> --broadcast --verify
 * ```
 * Note that upgrades are subject to a timelock period (default 2 days). You'll need to run the
 * script twice: once to queue the upgrade, and again after the timelock period to execute it.
 *
 */