// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MultiOnesAccess} from "../src/MultiOnesAccess.sol";

contract BatchAddKyc is Script {
    function run() public {
        uint256 operatorPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address accessAddress = vm.envAddress("SEPOLIA_MULTIONES_ACCESS");
        
        address[] memory users = new address[](2);
        users[0] = vm.envAddress("ADDRESS_USER");
        users[1] = vm.envAddress("ADDRESS_ADMIN");

        vm.startBroadcast(operatorPrivateKey);
        MultiOnesAccess access = MultiOnesAccess(accessAddress);
        
        access.kycPassBatch(users);
        
        console.log("Batch KYC passed for:");
        for(uint i=0; i<users.length; i++) {
            console.log("-", users[i]);
        }

        vm.stopBroadcast();
    }
}

