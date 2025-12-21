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
    address public underlyingAsset;
    address public multionesOracle;

    // Track all deployed RWA Tokens
    mapping(address => bool) public isRwaToken;
    address[] public allRwaTokens;


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

    function initialize(
        address _underlyingAsset,
        address _multionesOracle,
        address _multionesAccess
    ) public initializer {
        require(_underlyingAsset != address(0), "Factory: zero asset");
        require(_multionesOracle != address(0), "Factory: zero oracle");
        require(_multionesAccess != address(0), "Factory: zero access");
        
        underlyingAsset = _underlyingAsset;
        multionesOracle = _multionesOracle;
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

    function createRwaToken(
        string memory name,
        string memory symbol
    ) public onlyOwner returns (address) {
        // Encode initialization data
        bytes memory data = abi.encodeWithSelector(
            RWAToken.initialize.selector,
            underlyingAsset,
            multionesOracle,
            address(multionesAccess),
            name,
            symbol
        );

        // Deploy BeaconProxy
        BeaconProxy proxy = new BeaconProxy(address(beacon), data);
        address newTokenAddress = address(proxy);

        // Register new token
        isRwaToken[newTokenAddress] = true;
        allRwaTokens.push(newTokenAddress);

        // Event
        emit RWATokenCreated(newTokenAddress, name, symbol, underlyingAsset);

        return newTokenAddress;
    }


    // =========================== View Functions ==========================
    function getRwaTokenCount() public view returns (uint256) {
        return allRwaTokens.length;
    }

    function getRwaTokenAtIndex(uint256 index) public view returns (address) {
        return allRwaTokens[index];
    }

    function getRwaTokens(uint256 cursor, uint256 size) public view returns (address[] memory) {
        uint256 length = allRwaTokens.length;
        if (cursor >= length) {
            return new address[](0);
        }
        
        uint256 effectiveSize = size;
        if (cursor + size > length) {
            effectiveSize = length - cursor;
        }

        address[] memory tokens = new address[](effectiveSize);
        for (uint256 i = 0; i < effectiveSize; i++) {
            tokens[i] = allRwaTokens[cursor + i];
        }
        return tokens;
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
