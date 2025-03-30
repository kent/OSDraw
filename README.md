# OSDraw: Smart Contract Lottery System

OSDraw is a modular, upgradeable smart contract lottery system built on Ethereum. It features daily draws and configurable prize pools with transparent odds.

## Features

- **Daily Draws**: Automatic daily lottery draws
- **Multiple Prize Pools**: Create and manage multiple prize pools with different configurations
- **Upgradeable**: Uses the UUPS proxy pattern for future upgrades without losing state
- **VRF Integration**: Support for Chainlink VRF (or similar) for verifiable randomness
- **Modular Architecture**: Clean separation of concerns for better maintainability

## Architecture

The system is built with a modular approach, separating different functions into their own contracts:

- **OSDraw.sol**: Main entry point that inherits all functionality
- **OSDrawStorage.sol**: Central storage pattern for all state variables
- **Features/**
  - **OSDrawConfig.sol**: Configuration parameters and constants
  - **OSDrawTickets.sol**: Ticket purchase and management
  - **OSDrawPools.sol**: Pool creation and management
  - **OSDrawDraw.sol**: Drawing functionality
  - **OSDrawVRF.sol**: Verifiable random function integration
- **Model/**
  - **Pool.sol**: Pool data structure
  - **Ticket.sol**: Ticket data structure
  - **Config.sol**: System configuration data structure

## Getting Started

### Prerequisites

- Node.js v16+
- Foundry (for compilation, testing, and deployment)

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/osdraw.git
   cd osdraw
   ```

2. Install dependencies
   ```bash
   forge install
   ```

3. Compile the contracts
   ```bash
   forge build
   ```

4. Run tests
   ```bash
   forge test
   ```

### Deployment

The deployment process uses Foundry scripts. Create an `.env` file with the following variables:

```
PRIVATE_KEY=your_private_key_here
OPENSOURCE_RECIPIENT=0x...
ADMIN_ADDRESS=0x...
MANAGER_ADDRESS=0x...
```

Then run:

```bash
source .env
forge script script/DeployOSDraw.s.sol:DeployOSDraw --rpc-url https://rpc-url-for-your-network --broadcast --verify
```

See `script/DeployOSDraw.s.sol` for detailed deployment instructions.

## Contract Interaction

### Buying Tickets

Users can buy tickets for the daily draw:

```solidity
// Buy 1 ticket for the daily draw
osdraw.buyTickets{value: 0.01 ether}(1);

// Buy tickets for a specific pool
osdraw.buyPoolTickets{value: 0.05 ether}(poolId, 5);
```

### Admin Functions

Admins can manage pools:

```solidity
// Create a new pool
Pool memory newPool = Pool({
    ticketPrice: 0.01 ether,
    totalSold: 0,
    totalRedeemed: 0,
    ethBalance: 0,
    oddsBPS: oddsBPS,
    active: true
});
osdraw.createPool(newPool);

// Add liquidity to a pool
osdraw.addLiquidity{value: 1 ether}(poolId);

// Update a pool's configuration
osdraw.updatePool(poolId, updatedPool);
```

### Drawing

```solidity
// Perform the daily draw for the previous day
osdraw.performDailyDraw();

// Perform a draw for a specific pool
osdraw.performPoolDraw(poolId);
```

## Testing

The project includes comprehensive tests for all functionality. Run them with:

```bash
forge test
```

For more detailed test output:

```bash
forge test -vvv
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
