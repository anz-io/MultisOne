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

# Update Price
source .env && forge clean && forge script script/UpdatePrice.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Create
source .env && forge clean && forge script script/CreateIDO.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Subscribe
source .env && forge clean && forge script script/IDOSubscribe.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# KYC Verify
source .env && forge clean && forge script script/BatchAddKyc.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Settle
source .env && forge clean && forge script script/IDOSettle.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast

# IDO Claim
source .env && forge clean && forge script script/IDOClaim.s.sol \
    --rpc-url $RPC_SEPOLIA \
    -vvv --broadcast


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
            "Real World Asset 1" \
            "RWA1" \
        ) \
    ) \
    0x51648abb8de4a57d506cc7eb044ad0b003604942 \
    ./lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy
