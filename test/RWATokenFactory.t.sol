// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract RWATokenFactoryTest is BaseTest {
    function test_CreateRwaToken() public {
        vm.prank(admin);
        address rwaAddress = factory.createRwaToken("RWA1", "RWA1");
        
        assertTrue(factory.isRwaToken(rwaAddress));
        assertEq(factory.getRwaTokenCount(), 1);
        assertEq(factory.getRwaTokenAtIndex(0), rwaAddress);
        
        RWAToken rwa = RWAToken(rwaAddress);
        assertEq(rwa.name(), "RWA1");
        assertEq(rwa.symbol(), "RWA1");
    }

    function test_GetRwaTokensPagination() public {
        vm.startPrank(admin);
        factory.createRwaToken("RWA1", "RWA1");
        factory.createRwaToken("RWA2", "RWA2");
        vm.stopPrank();

        address[] memory tokens = factory.getRwaTokens(0, 2);
        assertEq(tokens.length, 2);
    }

    function test_UpgradeBeacon() public {
        // Deploy new implementation logic (just reusing RWAToken for simplicity)
        RWAToken newImpl = new RWAToken();
        
        vm.prank(admin);
        factory.upgradeBeacon(address(newImpl));
        
        assertEq(factory.getImplementation(), address(newImpl));
    }
}

