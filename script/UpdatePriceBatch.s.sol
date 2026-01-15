// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MultiOnesOracle} from "../src/MultiOnesOracle.sol";

contract UpdatePriceBatch is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address oracleAddress = vm.envAddress("SEPOLIA_MULTIONES_ORACLE");

        address[] memory assets = new address[](5);
        assets[0] = vm.envAddress("SEPOLIA_RWA_1");
        assets[1] = vm.envAddress("SEPOLIA_RWA_2");
        assets[2] = vm.envAddress("SEPOLIA_RWA_3");
        assets[3] = vm.envAddress("SEPOLIA_RWA_4");
        assets[4] = vm.envAddress("SEPOLIA_RWA_5");

        uint256[] memory prices = new uint256[](5);
        uint256[] memory basePrices = new uint256[](5);
        basePrices[0] = 200;
        basePrices[1] = 220;
        basePrices[2] = 240;
        basePrices[3] = 260;
        basePrices[4] = 280;

        vm.startBroadcast(deployerPrivateKey);

        MultiOnesOracle oracle = MultiOnesOracle(oracleAddress);

        for (uint256 i = 0; i < assets.length; i++) {
            // Check if asset is active
            if (!oracle.isAssetActive(assets[i])) {
                oracle.setAssetStatus(assets[i], true);
                console.log("Activated asset:", assets[i]);
            }

            // Generate random price addition: 0.00 to 5.00
            // using keccak256 hash of block data and index for pseudo-randomness
            uint256 randomInt = uint256(
                keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))
            ) % 501; // 0 to 500

            // Price calculation: base * 1e18 + randomInt * 1e16
            // e.g. randomInt = 313 (3.13) -> 313 * 1e16 = 3.13e18
            prices[i] = (basePrices[i] * 1 ether) + (randomInt * 1e16);

            console.log("Asset:", assets[i]);
            console.log("Price:", prices[i]);
        }

        oracle.updatePriceBatch(assets, prices);
        console.log("Batch updated prices for 5 assets.");

        vm.stopBroadcast();
    }
}
