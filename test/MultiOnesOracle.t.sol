// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";

contract MultiOnesOracleTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.prank(priceUpdater);
        oracle.setAssetStatus(address(0x123), true); // Activate a dummy asset
    }

    function test_SetAssetStatus() public {
        vm.prank(priceUpdater);
        oracle.setAssetStatus(address(0x123), false);
        assertFalse(oracle.isAssetActive(address(0x123)));
    }

    function test_UpdatePrice() public {
        vm.prank(priceUpdater);
        oracle.updatePrice(address(0x123), 100 * 1e18);
        
        (uint256 price, ) = oracle.getPriceSafe(address(0x123), 100);
        assertEq(price, 100 * 1e18);
    }

    function test_UpdatePriceBatch() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x123);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 200 * 1e18;

        vm.prank(priceUpdater);
        oracle.updatePriceBatch(tokens, prices);

        (uint256 price, ) = oracle.getPriceSafe(address(0x123), 100);
        assertEq(price, 200 * 1e18);
    }

    function test_GetPriceAtTime() public {
        vm.startPrank(priceUpdater);
        oracle.updatePrice(address(0x123), 100 * 1e18);
        vm.warp(block.timestamp + 100);
        oracle.updatePrice(address(0x123), 200 * 1e18);
        vm.stopPrank();

        ( , uint256 price1, ) = oracle.getPriceAtTime(address(0x123), block.timestamp - 100);
        assertEq(price1, 100 * 1e18);

        ( , uint256 price2, ) = oracle.getPriceAtTime(address(0x123), block.timestamp);
        assertEq(price2, 200 * 1e18);
    }

    function test_StalePriceRevert() public {
        vm.prank(priceUpdater);
        oracle.updatePrice(address(0x123), 100 * 1e18);
        
        vm.warp(block.timestamp + 1000);
        
        vm.expectRevert("MultiOnesOracle: price stale");
        oracle.getPriceSafe(address(0x123), 100);
    }
}

