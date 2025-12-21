// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {RWAToken} from "./RWAToken.sol";
import {MultiOnesConstants} from "./MultiOnesAccess.sol";

contract RWATokenFactory is 
    UUPSUpgradeable,
    Initializable,
    MultiOnesConstants
{
    // ============================== Storage ==============================
    UpgradeableBeacon public beacon;
    IAccessControl public multionesAccess;

    // Track all deployed RWA Tokens
    mapping(address => bool) public isRWAToken;
    address[] public allRWATokens;


    // =============================== Events ==============================
    event RWATokenCreated(
        address indexed tokenAddress, 
        string name, 
        string symbol, 
        address underlyingAsset
    );
    event BeaconUpdated(address indexed newImplementation);


    // ======================= Modifier & Constructor ======================
    modifier onlyOwner() {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _multionesAccess) public initializer {
        require(_multionesAccess != address(0), "Factory: zero address");
        multionesAccess = IAccessControl(_multionesAccess);

        address rwaImplementation = address(new RWAToken());
        beacon = new UpgradeableBeacon(rwaImplementation, address(this));
    }


    // ========================= Internal functions ========================
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    function upgradeBeacon(address newImplementation) public onlyOwner {
        beacon.upgradeTo(newImplementation);
        emit BeaconUpdated(newImplementation);
    }

    function createRWAToken(
        address asset,
        address oracle,
        string memory name,
        string memory symbol
    ) public onlyOwner returns (address) {
        // Check parameters
        require(asset != address(0), "Factory: zero asset");
        require(oracle != address(0), "Factory: zero oracle");

        // Encode initialization data
        bytes memory data = abi.encodeWithSelector(
            RWAToken.initialize.selector,
            asset,
            oracle,
            address(multionesAccess),
            name,
            symbol
        );

        // Deploy BeaconProxy
        BeaconProxy proxy = new BeaconProxy(address(beacon), data);
        address newTokenAddress = address(proxy);

        // Register new token
        isRWAToken[newTokenAddress] = true;
        allRWATokens.push(newTokenAddress);

        // Event
        emit RWATokenCreated(newTokenAddress, name, symbol, asset);

        return newTokenAddress;
    }


    // =========================== View Functions ==========================
    function getAllRWATokens() public view returns (address[] memory) {
        return allRWATokens;
    }

    function getBeacon() public view returns (address) {
        return address(beacon);
    }

    function getImplementation() public view returns (address) {
        return beacon.implementation();
    }


    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}

