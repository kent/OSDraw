# OSDraw - Open Source Daily Draw System

## Overview

OSDraw is a decentralized lottery system built on the Ethereum blockchain using Solidity. It combines the excitement of daily draws and special prize pools with a commitment to supporting open source development. A significant, fixed portion (50%) of all funds collected through ticket sales is automatically allocated to a designated open source project recipient.

The system is designed with security and transparency in mind, utilizing upgradeable contracts (UUPS pattern), a timelock mechanism for sensitive operations, integration with a Verifiable Random Function (VRF) provider for fair randomness, and a pull-payment system for secure fund withdrawals.

## Core Features

*   **Daily Lottery:** Users can purchase tickets daily for a chance to win a portion of that day's prize pot.
*   **Prize Pools:** Admins can create special prize pools with custom ticket prices and funding, offering additional winning opportunities.
*   **Open Source Funding:** A fixed 50% of all ticket revenue (from both daily and pool sales) is automatically designated for an Open Source Recipient address.
*   **Role-Based Access Control:** Different roles (Owner, Admin, Manager) have specific permissions for managing the system.
*   **VRF Integration:** Ensures provably fair winner selection using an external VRF provider.
*   **Upgradeable:** Built using the UUPS proxy pattern, allowing for future upgrades with a safety timelock.
*   **Secure Withdrawals:** Implements the pull-payment pattern to mitigate reentrancy risks.

## How it Works

### System Architecture

OSDraw utilizes a modular design:

1.  **`OSDraw.sol`:** The main entry point contract. It inherits functionality from feature contracts and manages initialization and upgrades.
2.  **Feature Contracts (`src/features/`)**:
    *   `OSDrawDraw.sol`: Handles the logic for triggering daily and pool draws. Includes anti-front-running cooldown for daily tickets.
    *   `OSDrawPools.sol`: Manages the creation, configuration, and funding of specific prize pools.
    *   `OSDrawTickets.sol`: Handles the purchase logic for both daily and pool tickets, including pricing tiers for daily tickets.
    *   `OSDrawVRF.sol`: Integrates with the external VRF provider, requests random numbers, and processes the VRF callback to determine winners and distribute funds (via pending payments).
    *   `OSDrawConfig.sol`: Manages system configuration like roles (Manager), timelock settings, and provides administrative functions like emergency withdrawal.
3.  **Storage (`OSDrawStorage.sol`)**: A central contract holding all system state variables in a dedicated storage slot to ensure smooth upgrades.
4.  **Models, Interfaces, Errors, Events (`src/model/`, `src/interfaces/`, `src/errors/`, `src/events/`)**: Define data structures, external contract interfaces, custom error types, and event definitions.
5.  **`Constants.sol`**: Defines key system parameters like fund splits, ticket prices, and identifiers.

### Roles

*   **Owner:** The address that deploys the contract. Has the highest level of control, including:
    *   Upgrading the contract implementation (subject to timelock).
    *   Setting the timelock delay duration.
    *   Executing emergency withdrawals (subject to timelock).
*   **Admin:** Configured during initialization. Responsibilities include:
    *   Creating, updating, activating, and deactivating prize pools (`OSDrawPools.sol`).
    *   Adding liquidity (ETH) to prize pools.
    *   Setting the address of the VRF entropy source (`OSDrawVRF.sol`).
    *   Receives a pre-configured percentage (`adminShare`) of the prize money from each draw.
*   **Manager:** Configured during initialization. Responsibilities include:
    *   Updating the `openSourceRecipient` address (`OSDrawConfig.sol`).
    *   Transferring the Manager role to a new address.
*   **Open Source Recipient:** Configured during initialization (can be updated by the Manager). Automatically designated to receive 50% (`PROJECT_SHARE`) of the funds from every draw.

### Daily Lottery Workflow

1.  **Initialization:** The Owner deploys the contract and initializes it, setting the `admin`, `manager`, `openSourceRecipient` addresses, and the `adminShare` percentage.
2.  **Ticket Purchase:** Users call `buyTickets(quantity)` on the `OSDraw` contract, sending the correct amount of ETH based on the tiered pricing (1, 5, 20, or 100 tickets).
    *   The ETH is added to the `dailyPot` mapping for the current day.
    *   The user's address is added to the `ticketsByDay` list for that day (if not already present), and their ticket count (`userTicketCountByDay`) is updated.
    *   Purchases are disallowed in the final hour of the UTC day (`DRAW_COOLDOWN`) to prevent front-running.
3.  **Triggering the Draw:** After a UTC day ends, *anyone* can call `performDailyDraw()`.
    *   The function checks that the draw for the *previous* day hasn't already run and that there were tickets sold.
    *   It calls `requestRandomDraw` on `OSDrawVRF.sol`, requesting a random number from the configured VRF provider. Callback information (pool ID = day ID, caller = receiver) is stored.
4.  **VRF Callback & Winner Selection:** The VRF provider calls `randomNumberCallback` on `OSDrawVRF.sol` with the requested random number.
    *   The callback verifies the caller is the VRF provider.
    *   It retrieves the corresponding day ID.
    *   It selects a winner using `randomNumber % participantCount` from the `ticketsByDay` list for that day.
5.  **Fund Distribution (Pull Payment):**
    *   The `dailyPot` for the drawn day is retrieved and cleared.
    *   Amounts are calculated: 50% for `openSourceRecipient`, `adminShare`% for `Admin`, remainder for the `winner`.
    *   These amounts are *not* transferred directly. Instead, they are added to the `_pendingPayments` mapping for each recipient address using `_addPendingPayment`.
6.  **Claiming Winnings:** The winner, Admin, and Open Source Recipient must individually call `withdrawPendingPayment()` to transfer their allocated ETH balance from the contract to their wallet.

### Prize Pool Workflow

1.  **Pool Creation:** The Admin calls `createPool(params)` on `OSDrawPools.sol`, specifying the `ticketPrice` and initial `active` status. Pools get unique IDs starting above `POOL_ID_THRESHOLD`.
2.  **Pool Funding (Optional):** The Admin can call `addLiquidity(poolId)` sending ETH to pre-fund a specific pool's prize pot.
3.  **Ticket Purchase:** Users call `buyPoolTickets(poolId, quantity)` on the `OSDrawTickets.sol` feature (accessible via `OSDraw.sol`), sending `ticketPrice * quantity` ETH.
    *   The ETH is added to the pool's `ethBalance`.
    *   The user's purchased ticket count for that pool is tracked (`tickets[poolId][userAddress]`).
    *   The user's address is added to the `poolParticipants` list for that pool (if not already present).
4.  **Triggering the Draw:** *Anyone* can call `performPoolDraw(poolId)` for an active pool with a non-zero balance.
    *   It calls `requestRandomDraw` on `OSDrawVRF.sol`, requesting a random number. Callback info (pool ID, caller = receiver) is stored.
5.  **VRF Callback & Winner Selection:** The VRF provider calls `randomNumberCallback` on `OSDrawVRF.sol`.
    *   The callback verifies the caller and retrieves the `poolId`.
    *   It selects a winner using `randomNumber % participantCount` from the `poolParticipants` list for that pool.
6.  **Fund Distribution (Pull Payment):**
    *   The pool's `ethBalance` is retrieved and cleared.
    *   Amounts are calculated: 50% for `openSourceRecipient`, `adminShare`% for `Admin`, remainder for the `winner`.
    *   Amounts are added to the `_pendingPayments` mapping for each recipient.
7.  **Claiming Winnings:** Recipients call `withdrawPendingPayment()` to claim their funds.

## Configuration & Setup

### Deployment & Initialization

1.  Deploy the `OSDraw.sol` contract. Note: Since it's upgradeable (UUPS), deploy it via a proxy deployer script using Foundry deploy scripts with OpenZeppelin Upgrades plugins.
2.  Immediately after deployment, call the `initialize()` function on the *proxy* contract address. This can only be called once.
    *   `_openSourceRecipient`: The address that will receive 50% of all draw proceeds.
    *   `_admin`: The address with permissions to manage pools and VRF settings.
    *   `_manager`: The address with permissions to change the recipient and transfer the manager role.
    *   `_adminShare`: The percentage (e.g., 5 for 5%) of the pot allocated to the admin. Must be less than 50.

### Setting up the VRF

1.  Choose a VRF provider compatible with the `IVRFSystem` interface expected by `OSDrawVRF.sol`.
2.  The Admin must call `setEntropySource(vrfProviderAddress)` on the `OSDraw` contract, providing the address of the chosen VRF provider contract.
3.  Ensure the `OSDraw` contract address is registered and funded with the VRF provider if required by their system to pay for randomness requests.

### Running the Daily Lottery

*   **Users:** Call `buyTickets(quantity)` sending the required ETH (check `getPrice(quantity)`).
*   **Keepers/Automation:** After each UTC day ends (00:00 UTC), a transaction needs to be sent calling `performDailyDraw()`. This can be automated using keeper networks (like Chainlink Keepers) or a simple script run via cron. This triggers the randomness request.
*   **VRF Interaction:** The VRF provider will eventually call back to `randomNumberCallback`. No user action is needed here.
*   **Claiming:** Winners, the Admin, and the Open Source Recipient need to call `withdrawPendingPayment()` to receive their funds. This could be done manually or via automated scripts checking `getPendingPayment(address)`.

### Managing Prize Pools

*   **Admin:**
    *   Call `createPool()` to set up a new pool with a ticket price.
    *   (Optional) Call `addLiquidity()` to add funds to the pool prize.
    *   Call `setPoolActive()` to make the pool available for ticket purchases or to deactivate it.
    *   Call `updatePool()` to change the price or active status later.
*   **Users:** Call `buyPoolTickets(poolId, quantity)` sending the required ETH (`pool.ticketPrice * quantity`).
*   **Keepers/Automation:** When a pool draw is desired (e.g., based on time, number of tickets sold, or manual trigger), call `performPoolDraw(poolId)`.
*   **VRF & Claiming:** Works the same as the daily lottery (VRF callback, `withdrawPendingPayment`).

## Security Considerations

*   **Upgradeability:** Upgrades are controlled by the Owner and are subject to a configurable timelock (default 2 days), providing time for community review.
*   **Access Control:** Roles ensure only authorized addresses can perform sensitive actions.
*   **Reentrancy:** Uses OpenZeppelin's `ReentrancyGuard` pattern (via the shared storage modifier) and pull payments to prevent reentrancy attacks during withdrawals and VRF callbacks.
*   **Randomness:** Fairness relies on the security and reliability of the chosen external VRF provider.
*   **Front-running:** Daily ticket purchases are paused 1 hour before the day ends to mitigate front-running the draw selection.
*   **Integer Overflows:** Basic checks are in place, especially for ticket quantity and price calculations. Uses Solidity ^0.8.20 which has default overflow checks.

---

*This README provides a detailed overview based on the contract code. Always perform thorough testing and auditing before deploying smart contracts to mainnet.*

## Contributing
1. Fork the project
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Additional Guidance

### Example VRF Setup

If you are using Chainlink VRF, for example, you might deploy and configure the VRF provider like this:

```solidity
// ExampleVRFProvider.sol
interface IVRFSystem {
    function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256);
}

contract ExampleVRFProvider is IVRFSystem {
    function requestRandomNumberWithTraceId(uint256 traceId) external override returns (uint256) {
        // Implementation logic for requesting randomness
        // Possibly emit an event to be fulfilled by an oracle
        // ...
        return block.number; // Example only (not truly random!)
    }
}
```

Then, in your deployment script or setup flow:
1. Deploy the VRF provider (e.g., ExampleVRFProvider).  
2. Call <code>osdraw.setEntropySource(vrfProviderAddress)</code> from the Admin account.

### Automating Daily Draws

Although anyone can call <code>performDailyDraw()</code>, automating it guarantees the daily lottery stays on schedule:  
- Use Chainlink Keepers (Automation): Register a keeper job that calls <code>performDailyDraw()</code> after each UTC day.  
- Use a Cron Script: Run a local or server-side cron job that triggers a transaction to <code>performDailyDraw()</code> once per day.

### UUPS Upgrade Example

Below is a simplified example showing how you might upgrade the contract using a Foundry script:

```bash
# Example using a forge script (pseudo-commands):
forge script script/UpgradeOSDraw.s.sol:UpgradeOSDraw \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Ensure that your upgrade script:  
1. Fetches the current proxy address.  
2. Uses the UUPS <code>upgradeTo</code> logic.  
3. Waits for the timelock delay if your contract enforces it.

### System Diagram

Here's a brief conceptual flow:

User Buys Ticket → OSDraw Contract → VRF Request → VRF Callback  
&nbsp; &nbsp; (funds dailyPot or pool) &nbsp;&nbsp;&nbsp; (randomness) &nbsp;&nbsp; (selects winner)

• Winners, Admin, and Open Source Recipient withdraw via pull-payment.  
• Admin can create/update pools, set VRF provider, and manage liquidity.  
• The Owner can upgrade the contract after the timelock period.

## Timelock Security

OSDraw uses OpenZeppelin's TimelockController to enforce a mandatory delay between proposing critical operations and executing them. This provides an essential security layer for contract governance.

### Why We Use a Timelock

The timelock mechanism serves several critical purposes:

1. **User Protection**: Users have time to exit the system before potentially dangerous operations (like contract upgrades) can be executed.

2. **Community Oversight**: The mandatory delay gives the community time to review and react to pending governance actions before they're executed.

3. **Multi-step Security**: By requiring two separate actions (scheduling and execution) with a time gap between them, timelocks protect against compromised owner keys and single-point failures.

4. **Front-running Protection**: Timelock prevents malicious actors from quickly executing harmful operations before users can respond.

### Protected Functions

The following critical operations are protected by the timelock:

1. **Contract Upgrades**: Any upgrade to the contract implementation through the UUPS pattern requires timelock protection.

2. **Emergency Withdrawals**: In case of emergency, funds can only be withdrawn after the timelock period has passed.

3. **Ownership Transfers**: Changing contract ownership must go through the timelock.

### How the Timelock Works

OSDraw uses a role-based timelock with the following structure:

1. **Proposer Role**: Addresses with this role can schedule operations. This is typically assigned to a DAO or multisig wallet.

2. **Executor Role**: Addresses with this role can execute operations after the timelock delay has passed. This can be the same as the proposer or a separate entity.

3. **Canceller Role**: Addresses that can cancel pending operations.

4. **Admin Role**: Can manage the above roles. Typically, this role is given to the timelock itself for self-governance.

The workflow for any timelock-protected operation is:

1. A proposer schedules the operation.
2. The mandatory delay period begins (default: 2 days).
3. After the delay expires, an executor can execute the operation.
4. At any point before execution, a canceller can cancel the scheduled operation.

This implementation offers more fine-grained control over the governance process compared to simpler timelocks, with distinct addresses potentially handling different steps of the process.
