// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {RWATokenFactory} from "../src/RWATokenFactory.sol";

contract UpgradeAll is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        
        vm.startBroadcast(deployerPrivateKey);

        // Options for upgrades
        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        // ---------------------------------------------------------
        // 1. Upgrade MultiOnesAccess
        // ---------------------------------------------------------
        address accessProxy = vm.envAddress("SEPOLIA_MULTIONES_ACCESS");
        console.log("Upgrading MultiOnesAccess at:", accessProxy);
        Upgrades.upgradeProxy(accessProxy, "MultiOnesAccess.sol:MultiOnesAccess", "", opts);
        console.log("MultiOnesAccess upgraded.");

        // ---------------------------------------------------------
        // 2. Upgrade MultiOnesOracle
        // ---------------------------------------------------------
        address oracleProxy = vm.envAddress("SEPOLIA_MULTIONES_ORACLE");
        console.log("Upgrading MultiOnesOracle at:", oracleProxy);
        Upgrades.upgradeProxy(oracleProxy, "MultiOnesOracle.sol:MultiOnesOracle", "", opts);
        console.log("MultiOnesOracle upgraded.");

        // ---------------------------------------------------------
        // 3. Upgrade RWATokenFactory (The Factory itself)
        // ---------------------------------------------------------
        address factoryProxy = vm.envAddress("SEPOLIA_RWA_FACTORY");
        console.log("Upgrading RWATokenFactory at:", factoryProxy);
        Upgrades.upgradeProxy(factoryProxy, "RWATokenFactory.sol:RWATokenFactory", "", opts);
        console.log("RWATokenFactory upgraded.");

        // ---------------------------------------------------------
        // 4. Upgrade IDO
        // ---------------------------------------------------------
        address idoProxy = vm.envAddress("SEPOLIA_MULTIONES_IDO");
        console.log("Upgrading IDO at:", idoProxy);
        Upgrades.upgradeProxy(idoProxy, "IDO.sol:IDO", "", opts);
        console.log("IDO upgraded.");

        // ---------------------------------------------------------
        // 5. Upgrade RWAToken Implementation (via Beacon in Factory)
        // ---------------------------------------------------------
        RWATokenFactory factory = RWATokenFactory(
            vm.envAddress("SEPOLIA_RWA_FACTORY")
        );
        address newImplementation = Upgrades.deployImplementation(
            "RWAToken.sol:RWAToken", opts
        );
        console.log("New RWAToken Implementation deployed at:", newImplementation);

        address beaconAddress = factory.getBeacon();
        console.log("Upgrading Beacon at:", beaconAddress);
        
        factory.upgradeBeacon(newImplementation);
        console.log("Beacon upgraded successfully!");

        vm.stopBroadcast();
    }
}
