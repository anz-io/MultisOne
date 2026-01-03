// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract ConfigFees is Script {
    function run() public {
        address rwaAddress = vm.envAddress("SEPOLIA_RWA_1");
        address feeCollector = vm.envAddress("ADDRESS_ADMIN");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        vm.startBroadcast(deployerPrivateKey);
        
        RWAToken rwa = RWAToken(rwaAddress);
        console.log("Configuring fees for RWA Token at:", rwaAddress);
        
        // 1. Set Fees: Buy 2% (200 bps), Sell 3% (300 bps)
        // 100 bps = 1%
        console.log("Setting fees: Buy = 2%, Sell = 3%");
        rwa.setFees(200, 300);

        // 2. Set Fee Collector
        console.log("Setting fee collector to:", feeCollector);
        rwa.setFeeCollector(feeCollector);

        vm.stopBroadcast();
    }
}

