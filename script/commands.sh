# =========================== Deploy ===========================
# Simulate
source .env && forge clean && forge script script/DeployCore.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv # --broadcast --verify 

# Deploy contracts
source .env && forge clean && forge script script/DeployCore.s.sol \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    -vvv --broadcast --verify

# Deploy RWA
source .env && forge clean && forge script script/DeployRWA.s.sol \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    -vvv --broadcast --verify


# =========================== Upgrade ===========================
# Upgrade RWA Token Contract (Beacon)
source .env && forge clean && forge script script/UpgradeRWA.s.sol \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    -vvv --broadcast --verify

# Upgrade All Contracts
source .env && forge clean && forge script script/UpgradeAll.s.sol \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    -vvv --broadcast --verify


# =========================== Price ===========================
# Update Price
source .env && forge script script/UpdatePrice.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# Update Price Batch
source .env && forge script script/UpdatePriceBatch.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast


# =========================== IDO ===========================
# IDO Create
source .env && forge script script/CreateIDO.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Subscribe
source .env && forge script script/IDOSubscribe.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Settle
source .env && forge script script/IDOSettle.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Claim
source .env && forge script script/IDOClaim.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast


# =========================== KYC ===========================
# KYC Verify
source .env && forge script script/BatchAddKyc.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast


# =========================== Fees ===========================
# Config RWA Token Fees
source .env && forge script script/ConfigFees.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast


# =========================== Verify ===========================
# Verify RWA Token Implementation
source .env && forge verify-contract \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    --compiler-version 0.8.28 \
    --watch \
    0xb149F66849AfC43544DbDb14820DfD7CAa649EA1 \
    ./src/RWAToken.sol:RWAToken

# Verify RWA Token Proxy
source .env && forge verify-contract \
    --rpc-url $RPC_SEPOLIA \
    --etherscan-api-key $API_ETHERSCAN \
    --compiler-version 0.8.28 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" \
        $SEPOLIA_RWA_FACTORY_BEACON \
        $(cast calldata "initialize(address,address,address,string,string)" \
            $MOCK_USDC \
            $SEPOLIA_MULTIONES_ORACLE \
            $SEPOLIA_MULTIONES_ACCESS \
            "Test-Normal-Started" \
            "TEST5" \
        ) \
    ) \
    $SEPOLIA_RWA_5 \
    ./lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy




# Create new RWA token
source .env && cast send $SEPOLIA_RWA_FACTORY \
    "createRwaToken(string,string)" \
    "Test-Normal" "TEST4" \
    --rpc-url $RPC_SEPOLIA \
    --private-key $PRIVATE_KEY_ADMIN

source .env && cast send $SEPOLIA_MULTIONES_IDO \
    "updateIdoTimes(uint256,uint64,uint64)" \
    6 1768460268 $(date -v+60S +%s) \
    --rpc-url $RPC_SEPOLIA \
    --private-key $PRIVATE_KEY_ADMIN

source .env && cast send $SEPOLIA_RWA_2 \
    "setBuyDuration(uint64,uint64)" \
    1768633200 1768719600 \
    --rpc-url $RPC_SEPOLIA \
    --private-key $PRIVATE_KEY_ADMIN
