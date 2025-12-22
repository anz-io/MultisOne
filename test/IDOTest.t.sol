// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IDO} from "../src/IDO.sol";
import {RWAToken} from "../src/RWAToken.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract IDOTest is BaseTest {
    IDO public ido;
    RWAToken public rwa;
    uint256 public idoId;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        address rwaAddress = factory.createRwaToken("RWA1", "RWA1");
        rwa = RWAToken(rwaAddress);

        // Deploy IDO Contract
        address idoProxy = Upgrades.deployUUPSProxy(
            "IDO.sol:IDO",
            abi.encodeCall(IDO.initialize, (address(usdc), address(access)))
        );
        ido = IDO(idoProxy);

        // Grant Whitelist Role to IDO contract to distribute tokens
        vm.prank(admin);
        access.grantRole(WHITELIST_TRANSFER_ROLE, address(ido));

        // Create IDO
        vm.prank(admin);
        idoId = ido.createIdo(
            address(rwa),
            1000 * 1e6,  // Target Raise (1:1)
            uint64(block.timestamp + 100),
            uint64(block.timestamp + 1000)
        );
    }

    function test_Subscribe() public {
        vm.warp(block.timestamp + 100); // Start IDO

        vm.startPrank(user1);
        usdc.approve(address(ido), 500 * 1e6);
        ido.subscribe(idoId, 500 * 1e6);
        vm.stopPrank();

        IDO.UserInfo memory uInfo = ido.getUserInfo(idoId, user1);
        assertEq(uInfo.subscribedAmount, 500 * 1e6);
    }

    function test_WithdrawAndDepositRwa() public {
        vm.warp(block.timestamp + 100);
        vm.startPrank(user1);
        usdc.approve(address(ido), 1000 * 1e6);
        ido.subscribe(idoId, 500 * 1e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000); // End IDO

        // Withdraw Funds
        vm.prank(teller);
        ido.withdrawFunds(idoId);
        assertEq(usdc.balanceOf(teller), 100500 * 1e6);

        vm.prank(kycOperator);
        access.kycPass(teller);

        // Mock Oracle for RWA minting
        vm.startPrank(priceUpdater);
        oracle.setAssetStatus(address(rwa), true);
        oracle.updatePrice(address(rwa), 250 * 1e18);
        vm.stopPrank();

        vm.startPrank(teller);
        usdc.approve(address(rwa), 500 * 1e6);
        rwa.deposit(500 * 1e6, teller); // Mint 1000 RWA to teller
        
        rwa.approve(address(ido), 2 * 1e18);
        ido.depositRwa(idoId, 2 * 1e18);
        vm.stopPrank();

        // Allow Claim
        vm.prank(teller);
        ido.allowClaim(idoId);

        // Claim
        vm.prank(user1);
        ido.claim(idoId);
        assertEq(rwa.balanceOf(user1), 2 * 1e18);
    }

    function test_CancelIdo() public {
        vm.prank(admin);
        ido.cancelIdo(idoId);
        
        IDO.IdoInfo memory info = ido.getIdoInfo(idoId);
        assertTrue(info.adminStatus == IDO.AdminStatus.Cancelled);
    }
}

