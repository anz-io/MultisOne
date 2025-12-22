// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MultiOnesAccess} from "../src/MultiOnesAccess.sol";
import {MultiOnesOracle} from "../src/MultiOnesOracle.sol";
import {RWATokenFactory} from "../src/RWATokenFactory.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BaseTest is Test {
    MultiOnesAccess public access;
    MultiOnesOracle public oracle;
    RWATokenFactory public factory;
    MockUSDC public usdc;
    
    address public admin = address(0x1);
    address public teller = address(0x2);
    address public kycOperator = address(0x3);
    address public priceUpdater = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);

    bytes32 public constant DEFAULT_ADMIN_ROLE_OVERRIDE = 0x00;
    bytes32 public constant KYC_OPERATOR_ROLE = keccak256("KYC_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant KYC_VERIFIED_USER_ROLE = keccak256("KYC_VERIFIED_USER_ROLE");
    bytes32 public constant TELLER_OPERATOR_ROLE = keccak256("TELLER_OPERATOR_ROLE");
    bytes32 public constant WHITELIST_TRANSFER_ROLE = keccak256("WHITELIST_TRANSFER_ROLE");

    function setUp() public virtual {
        vm.startPrank(admin);

        // Deploy Access
        address accessProxy = Upgrades.deployUUPSProxy(
            "MultiOnesAccess.sol:MultiOnesAccess",
            abi.encodeCall(MultiOnesAccess.initialize, ())
        );
        access = MultiOnesAccess(accessProxy);

        // Grant Roles
        access.grantRole(KYC_OPERATOR_ROLE, kycOperator);
        access.grantRole(PRICE_UPDATER_ROLE, priceUpdater);
        access.grantRole(TELLER_OPERATOR_ROLE, teller);

        // Deploy Oracle
        address oracleProxy = Upgrades.deployUUPSProxy(
            "MultiOnesOracle.sol:MultiOnesOracle",
            abi.encodeCall(MultiOnesOracle.initialize, (address(access)))
        );
        oracle = MultiOnesOracle(oracleProxy);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy Factory
        address factoryProxy = Upgrades.deployUUPSProxy(
            "RWATokenFactory.sol:RWATokenFactory",
            abi.encodeCall(RWATokenFactory.initialize, (address(usdc), address(oracle), address(access)))
        );
        factory = RWATokenFactory(factoryProxy);

        vm.stopPrank();

        // Distribute USDC
        usdc.mint(user1, 10000 * 1e6);
        usdc.mint(user2, 10000 * 1e6);
        usdc.mint(teller, 100000 * 1e6);
    }
}
