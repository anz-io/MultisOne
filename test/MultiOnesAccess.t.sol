// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";

contract MultiOnesAccessTest is BaseTest {
    function test_InitialRoles() public {
        assertTrue(access.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, admin));
        assertTrue(access.hasRole(KYC_OPERATOR_ROLE, kycOperator));
        assertTrue(access.hasRole(PRICE_UPDATER_ROLE, priceUpdater));
        assertTrue(access.hasRole(TELLER_OPERATOR_ROLE, teller));
    }

    function test_KycPass() public {
        vm.prank(kycOperator);
        access.kycPass(user1);
        assertTrue(access.isKycPassed(user1));
        assertEq(access.totalKycPassedAddresses(), 1);
    }

    function test_KycPassBatch() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(kycOperator);
        access.kycPassBatch(users);
        
        assertTrue(access.isKycPassed(user1));
        assertTrue(access.isKycPassed(user2));
        assertEq(access.totalKycPassedAddresses(), 2);
    }

    function test_KycRevoke() public {
        // Ensure KYC check is enabled
        vm.prank(admin);
        access.setKycCheckEnabled(true);

        vm.startPrank(kycOperator);
        access.kycPass(user1);
        access.kycRevoke(user1);
        vm.stopPrank();

        assertFalse(access.isKycPassed(user1));
        assertEq(access.totalKycPassedAddresses(), 0);
    }

    function test_KycRevokeBatch() public {
        // Ensure KYC check is enabled
        vm.prank(admin);
        access.setKycCheckEnabled(true);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.startPrank(kycOperator);
        access.kycPassBatch(users);
        access.kycRevokeBatch(users);
        vm.stopPrank();

        assertFalse(access.isKycPassed(user1));
        assertFalse(access.isKycPassed(user2));
        assertEq(access.totalKycPassedAddresses(), 0);
    }

    function test_KycCheckDisabled() public {
        // 1. Initially check enabled
        assertFalse(access.kycCheckEnabled()); 
        assertTrue(access.isKycPassed(user1));
        
        // 2. Enable check
        vm.prank(admin);
        access.setKycCheckEnabled(true);
        assertTrue(access.kycCheckEnabled());
        assertFalse(access.isKycPassed(user1));
        
        // Grant role
        vm.prank(kycOperator);
        access.kycPass(user1);
        assertTrue(access.isKycPassed(user1));
        
        // 3. Disable check again
        vm.prank(admin);
        access.setKycCheckEnabled(false);
        assertTrue(access.isKycPassed(user1)); // still has role
        assertTrue(access.isKycPassed(user2)); // no role, but check disabled
    }

    function test_RevertIfNotKycOperator() public {
        vm.prank(user1);
        vm.expectRevert();
        access.kycPass(user1);
    }
}

