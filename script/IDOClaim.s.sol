// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IDO} from "../src/IDO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDOClaim is Script {
    function run() public {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY_USER");
        
        address idoAddress = vm.envAddress("SEPOLIA_MULTIONES_IDO");
        uint256 idoId = 1;

        vm.startBroadcast(userPrivateKey);

        IDO ido = IDO(idoAddress);

        IDO.IdoInfo memory info = ido.getIdoInfo(idoId);
        require(info.adminStatus == IDO.AdminStatus.ClaimAllowed, "Claim not allowed yet");

        ido.claim(idoId);
        console.log("Claimed RWA from IDO", idoId);

        vm.stopBroadcast();
    }
}

