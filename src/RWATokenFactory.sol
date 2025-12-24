// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {RWAToken} from "./RWAToken.sol";
import {MultiOnesBase} from "./MultiOnesAccess.sol";

/// @title RWATokenFactory
/// @notice Factory contract for deploying RWA Tokens using the Beacon proxy pattern.
contract RWATokenFactory is 
    UUPSUpgradeable,
    Initializable,
    MultiOnesBase
{
    // ============================== Storage ==============================
    /// @notice The upgradeable beacon contract
    UpgradeableBeacon public beacon;
    
    /// @notice The underlying asset address (e.g., USDC) used for all RWA tokens
    address public underlyingAsset;
    
    /// @notice The oracle contract address
    address public multionesOracle;

    /// @notice Checks if an address is a deployed RWA token
    mapping(address => bool) public isRwaToken;
    
    /// @notice List of all deployed RWA tokens
    address[] public allRwaTokens;


    // =============================== Events ==============================
    /// @notice Emitted when a new RWA Token is created
    event RWATokenCreated(
        address indexed tokenAddress, 
        string name, 
        string symbol, 
        address underlyingAsset
    );
    
    /// @notice Emitted when the beacon implementation is updated
    event BeaconUpdated(address indexed newImplementation);


    // ============================ Constructor ============================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the factory
    /// @param _underlyingAsset The address of the underlying asset
    /// @param _multionesOracle The address of the oracle
    /// @param _multionesAccess The address of the access control
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
    /// @notice Authorizes the upgrade of the contract implementation
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {}


    // =========================== Admin Functions =========================
    /// @notice Upgrades the beacon to a new implementation
    /// @param newImplementation The address of the new implementation
    function upgradeBeacon(address newImplementation) public onlyOwner {
        beacon.upgradeTo(newImplementation);
        emit BeaconUpdated(newImplementation);
    }

    /// @notice Creates a new RWA Token
    /// @dev Should be called by the owner
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @return The address of the new token
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
    /// @notice Returns the total number of deployed RWA tokens
    function getRwaTokenCount() public view returns (uint256) {
        return allRwaTokens.length;
    }

    /// @notice Returns the RWA token at a specific index
    function getRwaTokenAtIndex(uint256 index) public view returns (address) {
        return allRwaTokens[index];
    }

    /// @notice Returns a list of RWA tokens with pagination
    /// @param cursor The starting index
    /// @param size The number of tokens to retrieve
    function getRwaTokens(
        uint256 cursor, 
        uint256 size
    ) public view returns (address[] memory) {
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

    /// @notice Returns the address of the beacon
    function getBeacon() public view returns (address) {
        return address(beacon);
    }

    /// @notice Returns the current implementation address of the beacon
    function getImplementation() public view returns (address) {
        return beacon.implementation();
    }


    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
