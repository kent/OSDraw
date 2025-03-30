// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../OSDrawStorage.sol";
import "../errors/OSDraw.sol";
import "../events/OSDraw.sol";
import "../model/Pool.sol";

/**
 * @title OSDrawPools
 * @dev Manages the creation and configuration of prize pools
 */
contract OSDrawPools is OSDrawStorage {
    // Basis points for percentage calculations (100% = 10000)
    uint16 private constant BPS = 10000;
    
    /**
     * Get details for a specific pool
     * @param poolId The ID of the pool
     * @return pool The pool information
     */
    function getPool(uint256 poolId) public view returns (Pool memory) {
        return _getStorage().pools[poolId];
    }
    
    /**
     * Create a new prize pool with the given parameters
     * @param params The pool parameters
     */
    function createPool(Pool calldata params) public onlyAdmin {
        Storage storage s = _getStorage();
        
        // Increment pool ID and create new pool
        uint256 newPoolId = s.config.currentPoolId + 1;
        s.config.currentPoolId = newPoolId;
        
        // Set pool parameters
        Pool storage pool = s.pools[newPoolId];
        pool.ticketPrice = params.ticketPrice;
        pool.totalSold = 0;
        pool.totalRedeemed = 0;
        pool.ethBalance = 0;
        pool.oddsBPS = params.oddsBPS;
        pool.active = params.active;
        
        emit PoolCreated(newPoolId, params.ticketPrice, params.active);
    }
    
    /**
     * Update an existing pool's configuration
     * @param poolId The ID of the pool to update
     * @param params The new pool parameters
     */
    function updatePool(uint256 poolId, Pool calldata params) public onlyAdmin {
        Storage storage s = _getStorage();
        
        // Check pool exists
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        
        // Update pool parameters
        pool.ticketPrice = params.ticketPrice;
        pool.oddsBPS = params.oddsBPS;
        pool.active = params.active;
        
        emit PoolUpdated(poolId, params.ticketPrice, params.active);
    }
    
    /**
     * Toggle a pool's active status
     * @param poolId The ID of the pool to update
     * @param active New active status
     */
    function setPoolActive(uint256 poolId, bool active) external onlyAdmin {
        Storage storage s = _getStorage();
        
        // Check pool exists
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        
        pool.active = active;
        
        emit PoolStatusChanged(poolId, active);
    }
    
    /**
     * Add ETH liquidity to a pool
     * @param poolId The ID of the pool
     */
    function addLiquidity(uint256 poolId) external payable onlyAdmin {
        Storage storage s = _getStorage();
        
        // Check pool exists
        Pool storage pool = s.pools[poolId];
        if (pool.ticketPrice == 0) revert PoolNotFound();
        if (msg.value == 0) revert InvalidAmount();
        
        pool.ethBalance += msg.value;
        
        emit LiquidityAdded(poolId, msg.value);
    }
    
    /**
     * Get all active pool IDs
     * @return poolIds Array of active pool IDs
     */
    function getActivePools() external view returns (uint256[] memory) {
        Storage storage s = _getStorage();
        
        // Count active pools
        uint256 count = 0;
        for (uint256 i = 1; i <= s.config.currentPoolId; i++) {
            if (s.pools[i].active) {
                count++;
            }
        }
        
        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        // Fill array with active pool IDs
        for (uint256 i = 1; i <= s.config.currentPoolId; i++) {
            if (s.pools[i].active) {
                result[index] = i;
                index++;
            }
        }
        
        return result;
    }
    
    /**
     * Access control: only admin can call functions with this modifier
     */
    modifier onlyAdmin() {
        if (msg.sender != _getStorage().admin) revert Unauthorized();
        _;
    }
} 