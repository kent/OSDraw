// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./features/OSDrawDraw.sol";
import "./features/OSDrawPools.sol";
import "./features/OSDrawConfig.sol";
import "./errors/OSDraw.sol";
import "./model/Constants.sol";

/**
 * @title OSDraw
 * @dev Main contract for the OS Draw system which combines lottery functionality with
 * charitable giving to open source projects
 *
 * The system allows users to buy tickets for daily draws and specific prize pools.
 * A percentage of all funds is dedicated to open source recipients.
 * 
 * The contract is designed to be upgradeable using the UUPS pattern and
 * uses a modular design with feature contracts.
 */
contract OSDraw is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    OSDrawDraw,
    OSDrawPools,
    OSDrawConfig
{
    // No need to redefine constants here, use from OSDrawStorage
    
    /**
     * @dev Initializes the contract and sets up the core configuration.
     * Can only be called once due to initializer modifier.
     * 
     * @param _openSourceRecipient Address that will receive the charitable portion of funds
     * @param _admin Address with administrative privileges
     * @param _manager Address with management capabilities
     * @param _adminShare Percentage of funds allocated to admin (must leave space for 50% to open source)
     */
    function initialize(
        address _openSourceRecipient,
        address _admin,
        address _manager,
        uint256 _adminShare
    ) public initializer {
        // Basic address validation
        if (_openSourceRecipient == address(0)) revert InvalidAddress();
        if (_admin == address(0)) revert InvalidAddress();
        if (_manager == address(0)) revert InvalidAddress();
        
        // Validate admin share - must leave space for open source percentage
        if (_adminShare == 0) revert InvalidPoolParameters();
        if (_adminShare + Constants.PROJECT_SHARE > Constants.PERCENT_DIVISOR) revert InvalidPoolParameters();
        
        // Validate that addresses are different to prevent confusion
        if (_openSourceRecipient == _admin || _openSourceRecipient == _manager || _admin == _manager) {
            revert InvalidAddress();
        }

        // Initialize parent contracts in the right order
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        // Setup storage
        Storage storage s = _getStorage();
        s.openSourceRecipient = _openSourceRecipient;
        s.admin = _admin;
        s.manager = _manager;
        s.adminShare = _adminShare;
        
        // Initialize config
        s.config.currentPoolId = 0;
        s.config.currentSupply = 0;
        s.config.owner = msg.sender;
        
        // Initialize reentrancy guard
        s.reentrancyStatus = NOT_ENTERED;
    }
    
    /**
     * @dev Constructor that disables initializers
     * Required by OZ upgradeable contracts pattern
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Resolve the conflict between the two getPrice implementations
     * by explicitly choosing one of them
     */
    function getPrice(uint256 quantity) public pure override(OSDrawTickets, OSDrawConfig) returns (uint256) {
        return OSDrawTickets.getPrice(quantity);
    }

    /**
     * @dev Authorization function for contract upgrades
     * @param newImpl Address of the new implementation
     */
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {
        // Create a unique operation ID for this upgrade
        bytes32 operationId = keccak256(abi.encode(
            "upgrade",
            newImpl,
            block.chainid
        ));
        
        // Get storage 
        Storage storage s = _getStorage();
        
        // Check if operation is queued and ready
        uint256 queuedTime = s.timelockOperations[operationId];
        if (queuedTime == 0) {
            // Queue the upgrade with default 2-day timelock if not set
            uint256 delay = s.timelockDelay > 0 ? s.timelockDelay : 2 days;
            uint256 executeTime = block.timestamp + delay;
            s.timelockOperations[operationId] = executeTime;
            
            emit OperationQueued(operationId, executeTime);
            revert("Upgrade queued, please try again after timelock expires");
        }
        
        // Ensure timelock has expired
        if (block.timestamp < queuedTime) {
            revert("Timelock not expired yet");
        }
        
        // Clear the timelock
        delete s.timelockOperations[operationId];
        
        // Emit upgrade event
        emit OperationExecuted(operationId);
    }
    
    // --- Public getters (required for backwards compatibility) ---
    
    /**
     * @dev Returns the admin address
     * @return Address of the admin
     */
    function admin() public view returns (address) {
        return _getStorage().admin;
    }
    
    /**
     * @dev Returns the manager address
     * @return Address of the manager
     */
    function manager() public view returns (address) {
        return _getStorage().manager;
    }
    
    /**
     * @dev Returns the open source recipient address
     * @return Address that receives open source funds
     */
    function openSourceRecipient() public view returns (address) {
        return _getStorage().openSourceRecipient;
    }
    
    /**
     * @dev Returns the admin share percentage
     * @return Percentage of funds allocated to admin
     */
    function adminShare() public view returns (uint256) {
        return _getStorage().adminShare;
    }
    
    /**
     * @dev Checks if a draw has been executed for a specific day
     * @param day The day ID to check
     * @return Boolean indicating if draw was executed
     */
    function drawExecuted(uint256 day) public view returns (bool) {
        return _getStorage().drawExecuted[day];
    }
    
    /**
     * @dev Returns the amount in the daily pot for a specific day
     * @param day The day ID to check
     * @return Amount of ETH in the pot
     */
    function dailyPot(uint256 day) public view returns (uint256) {
        return _getStorage().dailyPot[day];
    }
    
    /**
     * @dev Returns the contract version
     * @return Version number
     */
    function getVersion() external pure returns (uint256) {
        return 1;
    }
    
    /**
     * @dev Ensures only the admin can call the function
     * This override resolves the conflict between parent contracts
     */
    modifier onlyAdmin() override(OSDrawPools, OSDrawVRF) {
        if (msg.sender != _getStorage().admin) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Prevents reentrant calls
     * This override resolves the conflict between parent contracts
     */
    modifier nonReentrant() override(OSDrawPools, OSDrawVRF) {
        Storage storage s = _getStorage();
        require(s.reentrancyStatus != ENTERED, "ReentrancyGuard: reentrant call");
        s.reentrancyStatus = ENTERED;
        _;
        s.reentrancyStatus = NOT_ENTERED;
    }
} 