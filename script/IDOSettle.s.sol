// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IDO} from "../src/IDO.sol";
import {RWAToken} from "../src/RWAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDOSettle is Script {
    function run() public {
        uint256 tellerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        address teller = vm.addr(tellerPrivateKey);
        
        address idoAddress = vm.envAddress("SEPOLIA_MULTIONES_IDO");
        address rwaAddress = vm.envAddress("SEPOLIA_RWA_1");
        address usdcAddress = vm.envAddress("MOCK_USDC");
        uint256 idoId = 1;

        vm.startBroadcast(tellerPrivateKey);

        IDO ido = IDO(idoAddress);
        RWAToken rwa = RWAToken(rwaAddress);
        IERC20 usdc = IERC20(usdcAddress);

        // Check IDO Status
        IDO.IdoInfo memory info = ido.getIdoInfo(idoId);
        require(block.timestamp > info.endTime, "IDO not ended yet");

        // 1. Withdraw Funds
        uint256 withdrawnUsdc = 0;
        
        if (info.adminStatus == IDO.AdminStatus.Active) {
            uint256 originalBalance = usdc.balanceOf(teller);

            ido.withdrawFunds(idoId);
            console.log("Funds withdrawn.");

            uint256 newBalance = usdc.balanceOf(teller);
            withdrawnUsdc = newBalance - originalBalance;
            console.log("Withdrawn USDC amount:", withdrawnUsdc);
        }

        // 2. Prepare RWA (Mint to Teller using withdrawn USDC)
        uint256 rwaBalanceBefore = rwa.balanceOf(teller);
        
        // Approve USDC for RWA minting (deposit)
        usdc.approve(address(rwa), withdrawnUsdc); 
        
        // Mint RWA: deposit USDC -> get RWA
        // This uses the internal Oracle price automatically
        try rwa.deposit(withdrawnUsdc, teller) {
            console.log("Minted RWA to Teller via deposit");
        } catch Error(string memory reason) {
            console.log("Mint failed:", reason);
        } catch {
            console.log("Mint failed (unknown error)");
        }

        uint256 rwaBalanceAfter = rwa.balanceOf(teller);
        uint256 rwaGained = rwaBalanceAfter - rwaBalanceBefore;
        console.log("RWA Gained:", rwaGained);

        // 3. Deposit RWA to IDO
        // Refresh info
        info = ido.getIdoInfo(idoId);
        if (info.adminStatus == IDO.AdminStatus.Withdrawn && rwaGained > 0) {
            rwa.approve(address(ido), rwaGained);
            ido.depositRwa(idoId, rwaGained);
            console.log("RWA deposited to IDO.");
        }

        // 4. Allow Claim
        info = ido.getIdoInfo(idoId);
        if (info.adminStatus == IDO.AdminStatus.Settled) {
            ido.allowClaim(idoId);
            console.log("Claim allowed!");
        }

        vm.stopBroadcast();
    }
}

