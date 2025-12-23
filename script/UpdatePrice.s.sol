// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MultiOnesOracle} from "../src/MultiOnesOracle.sol";

contract UpdatePrice is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address oracleAddress = vm.envAddress("SEPOLIA_MULTIONES_ORACLE");
        address assetAddress = vm.envAddress("SEPOLIA_RWA_1");
        
        // Price with 18 decimals. e.g. 200e18 ~ $200
        uint256 price = 200e18; 

        vm.startBroadcast(deployerPrivateKey);

        MultiOnesOracle oracle = MultiOnesOracle(oracleAddress);
        
        // Ensure asset is active
        if (!oracle.isAssetActive(assetAddress)) {
            oracle.setAssetStatus(assetAddress, true);
            console.log("Activated asset:", assetAddress);
        }

        oracle.updatePrice(assetAddress, price);
        console.log("Updated price for", assetAddress, "to", price);

        vm.stopBroadcast();
    }
}
