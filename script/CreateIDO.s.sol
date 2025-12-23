// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IDO} from "../src/IDO.sol";
import {MultiOnesAccess} from "../src/MultiOnesAccess.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployIDO is Script {
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        
        address rwaAddress = vm.envAddress("SEPOLIA_RWA_1");   // Sale Token
        address idoAddress = vm.envAddress("SEPOLIA_MULTIONES_IDO");
        
        uint256 targetRaise = uint256(100_000 * 1e6); // Default 100k USDC
        uint64 startTime = uint64(block.timestamp + 60); // Default +1 minute
        uint64 endTime = uint64(block.timestamp + 3600); // Default +1 hour

        vm.startBroadcast(deployerPrivateKey);

        IDO ido = IDO(idoAddress);
        uint256 idoId = ido.createIdo(rwaAddress, targetRaise, startTime, endTime);
        console.log("IDO Created! ID:", idoId);
        console.log("Target Raise:", targetRaise);
        console.log("Start Time:", startTime);
        console.log("End Time:", endTime);

        vm.stopBroadcast();
    }
}

