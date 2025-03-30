// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./features/OSDrawDraw.sol";
import "./features/OSDrawPools.sol";

contract OSDraw is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    OSDrawDraw,
    OSDrawPools
{
    // --- Initializer (instead of constructor) ---
    function initialize(
        address _openSourceRecipient,
        address _admin,
        address _manager,
        uint256 _adminShare
    ) public initializer {
        require(_openSourceRecipient != address(0), "Invalid open source address");
        require(_admin != address(0), "Invalid admin address");
        require(_manager != address(0), "Invalid manager address");
        require(_adminShare + 50 < 100, "Invalid share config");

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        Storage storage s = _getStorage();
        s.openSourceRecipient = _openSourceRecipient;
        s.admin = _admin;
        s.manager = _manager;
        s.adminShare = _adminShare;
        
        // Initialize config
        s.config.currentPoolId = 0;
        s.config.currentSupply = 0;
        s.config.owner = msg.sender;
    }
    
    // --- Safe constructor ---
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // --- UUPS Upgrade Auth ---
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {}
    
    // --- Public getters (required for backwards compatibility) ---
    function admin() public view returns (address) {
        return _getStorage().admin;
    }
    
    function manager() public view returns (address) {
        return _getStorage().manager;
    }
    
    function openSourceRecipient() public view returns (address) {
        return _getStorage().openSourceRecipient;
    }
    
    function adminShare() public view returns (uint256) {
        return _getStorage().adminShare;
    }
    
    function drawExecuted(uint256 day) public view returns (bool) {
        return _getStorage().drawExecuted[day];
    }
    
    function dailyPot(uint256 day) public view returns (uint256) {
        return _getStorage().dailyPot[day];
    }
    
    // --- Version info ---
    function getVersion() external pure returns (uint256) {
        return 1;
    }
} 