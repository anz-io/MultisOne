// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract RWATokenTest is BaseTest {
    RWAToken public rwa;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        address rwaAddress = factory.createRwaToken("RWA1", "RWA1");
        rwa = RWAToken(rwaAddress);

        // Setup Oracle for RWA
        vm.prank(priceUpdater);
        oracle.setAssetStatus(address(rwa), true);
        vm.prank(priceUpdater);
        oracle.updatePrice(address(rwa), 1e18); // 1:1 price

        // Enable Normal Mode Buy/Sell
        vm.startPrank(admin);
        rwa.setBuyDuration(0, type(uint64).max);
        rwa.setSellDuration(0, type(uint64).max);
        vm.stopPrank();
    }

    function test_DepositWithdrawByTeller() public {
        vm.startPrank(user1);
        usdc.approve(address(rwa), 1000 * 1e6);
        vm.stopPrank();

        // Admin (Teller) deposits asset
        vm.startPrank(teller);
        usdc.mint(teller, 1000 * 1e6); // Ensure balance
        usdc.approve(address(rwa), 1000 * 1e6);
        rwa.depositAsset(1000 * 1e6);
        
        assertEq(usdc.balanceOf(address(rwa)), 1000 * 1e6);

        rwa.withdrawAsset(user1, 500 * 1e6);
        assertEq(usdc.balanceOf(address(rwa)), 500 * 1e6);
        vm.stopPrank();
    }

    function test_KycUserDeposit() public {
        vm.prank(teller);
        rwa.setIdoMode(false);

        vm.prank(kycOperator);
        access.kycPass(user1);

        vm.startPrank(user1);
        usdc.approve(address(rwa), 100 * 1e6);
        rwa.deposit(100 * 1e6, user1);
        assertEq(rwa.balanceOf(user1), 100 * 1e18);
        vm.stopPrank();
    }

    function test_TransferRestriction() public {
        vm.prank(admin);
        access.setKycCheckEnabled(true);

        vm.prank(teller);
        rwa.setIdoMode(false);

        vm.startPrank(kycOperator);
        access.kycPass(user1);
        // access.kycPass(user2); // User2 not verified yet
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(rwa), 100 * 1e6);
        rwa.deposit(100 * 1e6, user1);
        
        // Transfer should fail if not KYC verified
        vm.expectRevert("RWAToken: not KYC verified user");
        bool success1 = rwa.transfer(user2, 10 * 1e18);
        assertFalse(success1);
        vm.stopPrank();

        vm.prank(kycOperator);
        access.kycPass(user2);

        vm.prank(user1);
        bool success2 = rwa.transfer(user2, 10 * 1e18);
        assertTrue(success2);
        assertEq(rwa.balanceOf(user2), 10 * 1e18);
    }

    function test_SeparatedTeller() public {
        address localTeller = address(0x99);
        
        vm.prank(admin);
        rwa.setSeparatedTellerRole(localTeller, true);

        // Global teller should fail
        vm.prank(teller);
        vm.expectRevert("RWAToken: not teller");
        rwa.setIdoMode(false);

        // Local teller should succeed
        vm.prank(localTeller);
        rwa.setIdoMode(false);
        assertFalse(rwa.idoMode());
    }
}

