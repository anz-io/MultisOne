# MultisOne

MultisOne is a Real World Asset (RWA) tokenization protocol that includes Access Control, Oracle integration, and an Initial Decentralized Offering (IDO) mechanism. It leverages the UUPS upgradeability pattern for core contracts and the Beacon proxy pattern for RWA tokens to ensure scalability and maintainability.

## Project Structure

```
.
├── script/                  # Deployment and interaction scripts
│   ├── DeployCore.s.sol     # Deploys Access, Oracle, and Factory contracts
│   ├── DeployRWA.s.sol      # Deploys a new RWA Token instance
│   ├── CreateIDO.s.sol      # Creates a new IDO
│   └── ...                  # Scripts for KYC, IDO management, etc.
├── src/                     # Smart contracts
│   ├── MultiOnesAccess.sol  # Access control and KYC management
│   ├── MultiOnesOracle.sol  # On-chain oracle for asset prices
│   ├── RWATokenFactory.sol  # Factory for deploying RWA tokens via Beacon pattern
│   ├── RWAToken.sol         # ERC4626-compliant RWA token
│   ├── IDO.sol              # IDO management logic
│   └── interfaces/          # Contract interfaces
└── test/                    # Foundry tests
    ├── MultiOnesAccess.t.sol
    ├── RWAToken.t.sol
    └── ...
```

## Architecture Overview

1.  **MultiOnesAccess**: The central access control contract. It manages roles such as `KYC_OPERATOR_ROLE`, `PRICE_UPDATER_ROLE`, and `TELLER_OPERATOR_ROLE`. It also maintains the KYC status of users (`KYC_VERIFIED_USER_ROLE`), which is required for participating in RWA token activities.

2.  **MultiOnesOracle**: Stores asset prices and historical round data. It allows authorized price updaters to feed prices and supports retrieving prices at specific timestamps for accurate value calculation.

3.  **RWATokenFactory**: Responsible for deploying new `RWAToken` instances. It uses an `UpgradeableBeacon` to manage the implementation logic for all deployed RWA tokens. This ensures that all tokens can be upgraded simultaneously by updating the beacon.

4.  **RWAToken**: An ERC4626-compliant token representing the Real World Asset. It supports:
    *   **IDO Mode**: Restricts transfers and minting/burning to whitelisted addresses.
    *   **Normal Mode**: Allows broader interactions but still enforces KYC checks for deposits, mints, withdrawals, and redemptions.

5.  **IDO**: Manages the fundraising process. It handles subscription with payment tokens (e.g., USDC), enforces vesting/claim periods, and manages the distribution of RWA tokens to subscribers.

## Setup & Deployment

### Prerequisites

*   [Foundry](https://getfoundry.sh/)
*   Environment variables set in `.env` (refer to scripts for required variables like `RPC_SEPOLIA`, `API_ETHERSCAN`, private keys, etc.)

### Build & Test

To clean, build, and run tests:

```bash
forge clean && forge build && forge test
```

### Environment Variables

Copy `.env.example` to `.env` and fill in the following:

```bash
PRIVATE_KEY_ADMIN=...
RPC_SEPOLIA=...
API_ETHERSCAN=...
# After deployment, set these addresses in the .env file
SEPOLIA_MULTIONES_ACCESS=...
SEPOLIA_RWA_FACTORY=...
```

### Deployment Commands

See `script/commands.sh` for detailed command usage. Below are the key steps:

1.  **Deploy Core Contracts (Access, Oracle, Factory, IDO Logic)**:
    ```bash
    source .env && forge clean && forge script script/DeployCore.s.sol \
        --rpc-url $RPC_SEPOLIA \
        --etherscan-api-key $API_ETHERSCAN \
        -vvv --broadcast --verify
    ```

2.  **Deploy a New RWA Token**:
    ```bash
    source .env && forge clean && forge script script/DeployRWA.s.sol \
        --rpc-url $RPC_SEPOLIA \
        --etherscan-api-key $API_ETHERSCAN \
        -vvv --broadcast --verify
    ```

3.  **Upgrade RWA Token Logic (via Beacon)**:
    ```bash
    source .env && forge clean && forge script script/UpgradeRWA.s.sol \
        --rpc-url $RPC_SEPOLIA \
        -vvv --broadcast --verify
    ```

4.  **Interaction Scripts**:
    Refer to `script/commands.sh` for scripts related to:
    *   `UpdatePrice.s.sol`
    *   `CreateIDO.s.sol`
    *   `IDOSubscribe.s.sol`
    *   `BatchAddKyc.s.sol`
    *   `IDOSettle.s.sol`
    *   `IDOClaim.s.sol`
