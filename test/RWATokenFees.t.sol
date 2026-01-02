// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract RWATokenFeesTest is BaseTest {
    RWAToken public rwa;
    address public feeCollector = address(0xfee);

    uint256 public constant BUY_FEE_RATE = 500; // 5%
    uint256 public constant SELL_FEE_RATE = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    function setUp() public override {
        super.setUp();

        // 1. Create RWA Token
        vm.startPrank(admin);
        address rwaAddress = factory.createRwaToken("RWA1", "RWA1");
        rwa = RWAToken(rwaAddress);
        
        // 2. Setup Oracle
        vm.stopPrank();
        vm.startPrank(priceUpdater);
        oracle.setAssetStatus(address(rwa), true);
        oracle.updatePrice(address(rwa), 1e18); // 1 RWA = 1 USDC
        vm.stopPrank();

        // 3. Disable IDO Mode (Enable Trading)
        vm.prank(teller);
        rwa.setIdoMode(false);

        // 4. Set Fees
        vm.startPrank(admin);
        rwa.setFees(BUY_FEE_RATE, SELL_FEE_RATE);
        rwa.setFeeCollector(feeCollector);
        vm.stopPrank();

        // 5. KYC User1
        vm.prank(kycOperator);
        access.kycPass(user1);
    }

    function test_PreviewFunctions() public {
        // Price is 1:1. 
        // 100 USDC -> 5 USDC Fee -> 95 USDC Net -> 95 RWA.
        uint256 depositAssets = 100 * 1e6;
        uint256 expectedShares = 95 * 1e18;
        
        uint256 shares = rwa.previewDeposit(depositAssets);
        assertEq(shares, expectedShares, "previewDeposit mismatch");

        // 100 RWA -> 100 USDC Net. 
        // Gross = 100 / (1 - 0.05) = 105.263157... (round ceil -> 105263158)
        uint256 mintShares = 100 * 1e18;
        uint256 expectedAssets = 105263158; 
        uint256 assets = rwa.previewMint(mintShares);
        assertEq(assets, expectedAssets, "previewMint mismatch");

        // Withdraw 100 USDC (Net).
        // Gross = 100 / (1 - 0.02) = 102.040816...
        uint256 withdrawAssets = 100 * 1e6;
        uint256 expectedWithdrawShares = 102040817 * 1e12; 
        uint256 withdrawShares = rwa.previewWithdraw(withdrawAssets);
        assertEq(withdrawShares, expectedWithdrawShares, "previewWithdraw mismatch");

        // Redeem 100 RWA.
        // Gross = 100 RWA -> 100 USDC.
        uint256 redeemShares = 100 * 1e18;
        uint256 expectedRedeemAssets = 98 * 1e6;
        uint256 redeemAssets = rwa.previewRedeem(redeemShares);
        assertEq(redeemAssets, expectedRedeemAssets, "previewRedeem mismatch");
    }

    function test_Deposit() public {
        uint256 assets = 100 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(rwa), assets);
        
        // Check fee collector balance before.
        assertEq(usdc.balanceOf(feeCollector), 0);

        uint256 shares = rwa.deposit(assets, user1);
        vm.stopPrank();

        // 1. User shares: 95 * 1e18
        assertEq(shares, 95 * 1e18, "Shares minted mismatch");
        assertEq(rwa.balanceOf(user1), 95 * 1e18, "User balance mismatch");
        
        // 2. Fee Collector: 5 * 1e6
        assertEq(usdc.balanceOf(feeCollector), 5 * 1e6, "Fee collector balance mismatch");

        // 3. Vault Balance: 95 * 1e6
        assertEq(usdc.balanceOf(address(rwa)), 95 * 1e6, "Vault balance mismatch");
    }

    function test_Mint() public {
        // Mint 100 RWA.
        // Needs 105.263158 USDC.
        uint256 shares = 100 * 1e18;
        uint256 expectedCost = 105263158;
        
        vm.startPrank(user1);
        usdc.approve(address(rwa), expectedCost);
        
        uint256 cost = rwa.mint(shares, user1);
        vm.stopPrank();

        assertEq(cost, expectedCost, "Mint cost mismatch");
        assertEq(rwa.balanceOf(user1), shares, "User shares mismatch");

        // fee = gross * 5% = 105263158 * 500 / 10000 = 5263157.9 -> 5263157
        uint256 expectedFee = 5263157;
        assertEq(usdc.balanceOf(feeCollector), expectedFee, "Fee collector mismatch");
        
        // Vault balance = Cost - Fee
        assertEq(usdc.balanceOf(address(rwa)), cost - expectedFee, "Vault balance mismatch");
    }

    function test_Withdraw() public {
        // First deposit enough to withdraw.
        // Deposit 200 USDC -> 190 RWA.
        vm.startPrank(user1);
        usdc.approve(address(rwa), 200 * 1e6);
        rwa.deposit(200 * 1e6, user1);
        vm.stopPrank();

        // Withdraw 100 USDC.
        // Requires burning shares worth gross amount.
        // Gross = 100 / 0.98 = 102.0408163... -> 102.040817 USDC (Round Up)
        // Shares to burn = 102.040817 RWA.
        uint256 assetsToWithdraw = 100 * 1e6;
        uint256 expectedSharesBurned = 102040817 * 1e12;

        uint256 preBalance = rwa.balanceOf(user1);
        uint256 preFee = usdc.balanceOf(feeCollector); // Should be 10 USDC from deposit

        vm.startPrank(user1);
        uint256 sharesBurned = rwa.withdraw(assetsToWithdraw, user1, user1);
        vm.stopPrank();

        assertEq(sharesBurned, expectedSharesBurned, "Shares burned mismatch");
        // User balance: Initial 10000 - 200 + 100 = 9900
        assertEq(usdc.balanceOf(user1), (10000 * 1e6) - 200 * 1e6 + 100 * 1e6, "User USDC balance mismatch"); 
        assertEq(rwa.balanceOf(user1), preBalance - sharesBurned, "User RWA balance mismatch");

        // Fee Check
        // Fee = Gross - Net = 102040817 - 100000000 = 2040817
        uint256 fee = 2040817;
        assertEq(usdc.balanceOf(feeCollector) - preFee, fee, "Fee collector increment mismatch");
    }

    function test_Redeem() public {
        // Deposit 200 USDC -> 190 RWA.
        vm.startPrank(user1);
        usdc.approve(address(rwa), 200 * 1e6);
        rwa.deposit(200 * 1e6, user1);
        vm.stopPrank();

        // Redeem 100 RWA.
        // Gross = 100 USDC.
        // Fee = 2%. 2 USDC.
        // Net = 98 USDC.
        uint256 sharesToRedeem = 100 * 1e18;
        uint256 expectedAssets = 98 * 1e6;

        uint256 preFee = usdc.balanceOf(feeCollector);

        vm.startPrank(user1);
        uint256 assetsReceived = rwa.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();

        assertEq(assetsReceived, expectedAssets, "Assets received mismatch");
        assertEq(rwa.balanceOf(user1), 90 * 1e18, "User RWA remaining mismatch");

        // Fee Check
        // Fee = 2 USDC
        assertEq(usdc.balanceOf(feeCollector) - preFee, 2 * 1e6, "Fee collector increment mismatch");
    }
}
