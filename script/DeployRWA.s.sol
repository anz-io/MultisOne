// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RWATokenFactory} from "../src/RWATokenFactory.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract DeployRWA is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address factoryAddress = vm.envAddress("SEPOLIA_RWA_FACTORY");
        
        string memory name = string("Real World Asset 1");
        string memory symbol = string("RWA1");

        vm.startBroadcast(deployerPrivateKey);

        RWATokenFactory factory = RWATokenFactory(factoryAddress);
        
        address rwaAddress = factory.createRwaToken(name, symbol);
        console.log("RWAToken created at:", rwaAddress);
        console.log("Name:", name);
        console.log("Symbol:", symbol);

        vm.stopBroadcast();
    }
}

