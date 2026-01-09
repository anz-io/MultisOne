// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RWATokenFactory} from "../src/RWATokenFactory.sol";
import {RWAToken} from "../src/RWAToken.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeRWA is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address factoryAddress = vm.envAddress("SEPOLIA_RWA_FACTORY");

        vm.startBroadcast(deployerPrivateKey);
        RWATokenFactory factory = RWATokenFactory(factoryAddress);
        
        Options memory opts;
        address newImplementation = Upgrades.deployImplementation(
            "RWAToken.sol:RWAToken", opts
        );
        console.log("New RWAToken Implementation deployed at:", newImplementation);

        address beaconAddress = factory.getBeacon();
        console.log("Upgrading Beacon at:", beaconAddress);
        
        factory.upgradeBeacon(newImplementation);
        console.log("Beacon upgraded successfully!");

        uint256 count = factory.getRwaTokenCount();
        for (uint256 i = 0; i < count; i++) {
            address tokenAddr = factory.getRwaTokenAtIndex(i);
            RWAToken rwa = RWAToken(tokenAddr);
            rwa.setBuyDuration(0, type(uint64).max);
            rwa.setSellDuration(0, type(uint64).max);
            console.log("Updated RWAToken at:", tokenAddr);
        }

        vm.stopBroadcast();
    }
}
