// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MultiOnesConstants} from "./MultiOnesAccess.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";


contract MultiOnesOracle is MultiOnesConstants, Initializable, UUPSUpgradeable {

    struct PriceData {
        bool isActive;
        uint256 price;
        uint256 lastUpdate;
    }

    IAccessControl public multionesAccess;

    mapping(address => PriceData) public priceData;

    event AssetStatusChanged(address indexed token, bool isActive);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyPriceUpdater() {
        _checkPriceUpdater();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _multionesAccess) public initializer {
        multionesAccess = IAccessControl(_multionesAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _updatePriceInternal(address token, uint256 price) internal {
        require(priceData[token].isActive, "MultiOnesOracle: asset is not active");
        priceData[token] = PriceData({
            price: price,
            lastUpdate: block.timestamp,
            isActive: true
        });
        emit PriceUpdated(token, price, block.timestamp);
    }

    function _checkOwner() internal view {
        require(
            multionesAccess.hasRole(DEFAULT_ADMIN_ROLE_OVERRIDE, msg.sender), 
            "MultiOnesAccess: not owner"
        );
    }

    function _checkPriceUpdater() internal view {
        require(
            multionesAccess.hasRole(PRICE_UPDATER_ROLE, msg.sender), 
            "MultiOnesAccess: not price updater"
        );
    }


    function setAssetStatus(address token, bool isActive) public onlyPriceUpdater {
        priceData[token].isActive = isActive;
        emit AssetStatusChanged(token, isActive);
    }

    function updatePrice(address token, uint256 price) public onlyPriceUpdater {
        _updatePriceInternal(token, price);
    }

    function updatePriceBatch(
        address[] calldata tokens,
        uint256[] calldata prices
    ) public onlyPriceUpdater {
        require(
            tokens.length == prices.length, 
            "MultiOnesOracle: tokens and prices length mismatch"
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            _updatePriceInternal(tokens[i], prices[i]);
        }
    }

    function getPrice(
        address token
    ) external view returns (uint256, uint256) {
        PriceData memory data = priceData[token];
        require(data.isActive, "MultiOnesOracle: asset not supported");
        require(data.price > 0, "MultiOnesOracle: price not available");
        return (data.price, data.lastUpdate);
    }

    function getPriceSafe(
        address token, 
        uint256 maxTimeDelay
    ) external view returns (uint256, uint256) {
        PriceData memory data = priceData[token];
        require(data.isActive, "MultiOnesOracle: asset not supported");
        require(
            block.timestamp - data.lastUpdate <= maxTimeDelay, 
            "MultiOnesOracle: price stale"
        );
        return (data.price, data.lastUpdate);
    }

}