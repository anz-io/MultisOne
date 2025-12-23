// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IDO} from "../src/IDO.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract IDOSubscribe is Script {
    function run() public {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY_USER");
        address user = vm.addr(userPrivateKey);
        
        address idoAddress = vm.envAddress("SEPOLIA_MULTIONES_IDO");
        address usdcAddress = vm.envAddress("MOCK_USDC");
        uint256 idoId = 1;
        uint256 amount = 1_000 * 1e6;

        vm.startBroadcast(userPrivateKey);

        MockUSDC usdc = MockUSDC(usdcAddress);
        IDO ido = IDO(idoAddress);

        // 1. Mint USDC
        uint256 balance = usdc.balanceOf(user);
        if (balance < amount) {
            usdc.mint(user, 1_000_000 * 1e6);
            console.log("Minted USDC to user");
        }

        // 2. Approve USDC
        uint256 currentAllowance = usdc.allowance(user, idoAddress);
        if (currentAllowance < amount) {
            usdc.approve(idoAddress, amount);
            console.log("Approved USDC for IDO");
        }

        // 3. Subscribe
        ido.subscribe(idoId, amount);
        console.log("Subscribed to IDO", idoId, "with amount:", amount);

        vm.stopBroadcast();
    }
}

