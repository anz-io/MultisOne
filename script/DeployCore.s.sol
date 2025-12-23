// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {MultiOnesAccess} from "../src/MultiOnesAccess.sol";
import {MultiOnesOracle} from "../src/MultiOnesOracle.sol";
import {RWATokenFactory} from "../src/RWATokenFactory.sol";
import {IDO} from "../src/IDO.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract DeployCore is Script {
    // Roles
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant TELLER_OPERATOR_ROLE = keccak256("TELLER_OPERATOR_ROLE");
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Define addresses for roles (in real deployment, set these env vars)
        address kycOperator = vm.envOr("KYC_OPERATOR", deployer);
        address priceUpdater = vm.envOr("PRICE_UPDATER", deployer);
        address teller = vm.envOr("TELLER_OPERATOR", deployer);

        console.log("Deploying Core Contracts with deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Access Control
        address accessProxy = Upgrades.deployUUPSProxy(
            "MultiOnesAccess.sol:MultiOnesAccess",
            abi.encodeCall(MultiOnesAccess.initialize, ())
        );
        MultiOnesAccess access = MultiOnesAccess(accessProxy);
        console.log("MultiOnesAccess deployed at:", address(access));

        // 2. Deploy Oracle
        address oracleProxy = Upgrades.deployUUPSProxy(
            "MultiOnesOracle.sol:MultiOnesOracle",
            abi.encodeCall(MultiOnesOracle.initialize, (address(access)))
        );
        MultiOnesOracle oracle = MultiOnesOracle(oracleProxy);
        console.log("MultiOnesOracle deployed at:", address(oracle));

        // 3. Deploy Factory
        address usdcAddress = vm.envAddress("MOCK_USDC");
        address factoryProxy = Upgrades.deployUUPSProxy(
            "RWATokenFactory.sol:RWATokenFactory",
            abi.encodeCall(RWATokenFactory.initialize, (usdcAddress, address(oracle), address(access)))
        );
        RWATokenFactory factory = RWATokenFactory(factoryProxy);
        console.log("RWATokenFactory deployed at:", address(factory));

        // 4. Deploy IDO
        address idoProxy = Upgrades.deployUUPSProxy(
            "IDO.sol:IDO",
            abi.encodeCall(IDO.initialize, (usdcAddress, address(access)))
        );
        IDO ido = IDO(idoProxy);
        console.log("IDO deployed at:", address(ido));

        // 5. Grant Roles
        access.grantRole(KYC_OPERATOR_ROLE, kycOperator);
        access.grantRole(PRICE_UPDATER_ROLE, priceUpdater);
        access.grantRole(TELLER_OPERATOR_ROLE, teller);
        access.grantRole(WHITELIST_TRANSFER_ROLE, address(ido));
        console.log("Roles granted.");

        vm.stopBroadcast();
    }
}

