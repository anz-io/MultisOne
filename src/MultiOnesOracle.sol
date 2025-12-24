// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IMultiOnesOracle} from "./interfaces/IMultiOnesOracle.sol";
import {MultiOnesBase} from "./MultiOnesAccess.sol";

/// @title MultiOnesOracle
/// @notice Oracle contract for storing and retrieving asset prices.
contract MultiOnesOracle is 
    UUPSUpgradeable,
    Initializable,
    IMultiOnesOracle, 
    MultiOnesBase 
{
    // ============================== Storage ==============================
    struct PriceData {
        bool isActive;
        uint48 lastUpdate;
        uint256 price;
    }

    struct RoundData {
        uint80 roundId;
        uint48 updatedAt;
        uint256 price;
    }

    /// @notice Stores the latest price data for each asset
    mapping(address => PriceData) public priceData;

    /// @notice Stores the latest round ID for each asset
    mapping(address => uint80) public latestRoundId;

    /// @notice Mapping for RWA Token => round ID => round data
    mapping(address => mapping(uint80 => RoundData)) public historicalPrices;


    // =============================== Events ==============================
    /// @notice Emitted when an asset's active status changes
    event AssetStatusChanged(address indexed token, bool isActive);

    /// @notice Emitted when an asset's price is updated
    event PriceUpdated(address indexed token, uint48 timestamp, uint256 price, uint80 roundId);


    // ============================ Constructor ============================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the oracle contract
    /// @param _multionesAccess The address of the AccessControl contract
    function initialize(address _multionesAccess) public initializer {
        require(_multionesAccess != address(0), "MultiOnesOracle: zero address");
        multionesAccess = IAccessControl(_multionesAccess);
    }


    // ========================= Internal functions ========================
    /// @notice Authorizes the upgrade of the contract implementation
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {}

    /// @dev Internal function to update the price of an asset
    function _updatePriceInternal(address token, uint256 price) internal {
        require(priceData[token].isActive, "MultiOnesOracle: asset is not active");
        uint48 currentTimestamp = uint48(block.timestamp);
        
        uint80 newRoundId = latestRoundId[token] + 1;
        latestRoundId[token] = newRoundId;

        RoundData memory roundData = RoundData({
            roundId: newRoundId,
            updatedAt: currentTimestamp,
            price: price
        });

        historicalPrices[token][newRoundId] = roundData;

        priceData[token].price = price;
        priceData[token].lastUpdate = currentTimestamp;

        emit PriceUpdated(token, currentTimestamp, price, newRoundId);
    }


    // =========================== View functions ==========================
    /// @notice Checks if an asset is active
    /// @param token The address of the asset
    function isAssetActive(address token) public view returns (bool) {
        return priceData[token].isActive;
    }

    /// @notice Retrieves the current price of an asset, ensuring it's not stale
    /// @param token The address of the asset
    /// @param maxTimeDelay The maximum allowed delay in seconds
    /// @return price The current price
    /// @return delay The time elapsed since the last update
    function getPriceSafe(
        address token, 
        uint256 maxTimeDelay
    ) public view returns (uint256, uint256) {
        PriceData memory data = priceData[token];
        require(data.isActive, "MultiOnesOracle: asset not supported");
        require(
            block.timestamp - data.lastUpdate <= maxTimeDelay, 
            "MultiOnesOracle: price stale"
        );
        return (data.price, block.timestamp - data.lastUpdate);
    }

    /// @notice Retrieves the latest round data for an asset
    /// @param token The address of the asset
    function getLatestRoundData(
        address token
    ) public view returns (uint80, uint256, uint256) {
        require(priceData[token].isActive, "MultiOnesOracle: asset not supported");
        uint80 currentRoundId = latestRoundId[token];
        RoundData memory data = historicalPrices[token][currentRoundId];
        require(data.updatedAt > 0, "MultiOnesOracle: no data present");
        return (data.roundId, data.price, data.updatedAt);
    }

    /// @notice Retrieves historical round data for an asset
    /// @param token The address of the asset
    /// @param roundId The round ID to retrieve
    function getRoundData(
        address token, 
        uint80 roundId
    ) public view returns (uint80, uint256, uint256) {
        RoundData memory data = historicalPrices[token][roundId];
        require(data.updatedAt > 0, "MultiOnesOracle: no data for round");
        return (data.roundId, data.price, data.updatedAt);
    }

    /// @notice Retrieves the price of an asset at a specific timestamp
    /// @dev Uses binary search to find the closest price update before or at the timestamp
    /// @param token The address of the asset
    /// @param timestamp The target timestamp
    function getPriceAtTime(
        address token, 
        uint256 timestamp
    ) public view returns (uint80, uint256, uint256) {
        uint80 currentRoundId = latestRoundId[token];
        require(currentRoundId > 0, "MultiOnesOracle: no history");
        
        RoundData memory latest = historicalPrices[token][currentRoundId];
        if (timestamp >= latest.updatedAt) {
            return (latest.roundId, latest.price, latest.updatedAt);
        }

        RoundData memory first = historicalPrices[token][1];
        if (timestamp <= first.updatedAt) {
            return (first.roundId, first.price, first.updatedAt);
        }

        uint80 low = 1;
        uint80 high = currentRoundId;

        // Binary search for the closest round data
        while (low <= high) {
            uint80 mid = low + (high - low) / 2;
            RoundData memory midData = historicalPrices[token][mid];
            
            if (midData.updatedAt == timestamp) {
                return (midData.roundId, midData.price, midData.updatedAt);
            } else if (midData.updatedAt < timestamp) {
                if (mid == currentRoundId) {
                    return (midData.roundId, midData.price, midData.updatedAt);
                }
                RoundData memory nextData = historicalPrices[token][mid + 1];
                if (nextData.updatedAt > timestamp) {
                    return (midData.roundId, midData.price, midData.updatedAt);
                }
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }

        revert("MultiOnesOracle: timestamp not found");
    }


    // ====================== Write functions - admin ======================
    /// @notice Sets the active status of an asset
    /// @param token The address of the asset
    /// @param isActive The new status
    function setAssetStatus(address token, bool isActive) public onlyPriceUpdater {
        priceData[token].isActive = isActive;
        emit AssetStatusChanged(token, isActive);
    }

    /// @notice Updates the price of an asset
    /// @param token The address of the asset
    /// @param price The new price
    function updatePrice(address token, uint256 price) public onlyPriceUpdater {
        _updatePriceInternal(token, price);
    }

    /// @notice Batch updates prices for multiple assets
    /// @param tokens Array of asset addresses
    /// @param prices Array of new prices corresponding to the tokens
    function updatePriceBatch(
        address[] calldata tokens, 
        uint256[] calldata prices
    ) public onlyPriceUpdater {
        require(tokens.length == prices.length, "MultiOnesOracle: length mismatch");
        require(tokens.length <= MAX_BATCH_SIZE_LIMIT, "MultiOnesOracle: batch too large");
        for (uint256 i = 0; i < tokens.length; i++) {
            _updatePriceInternal(tokens[i], prices[i]);
        }
    }

    // =========================== Storage Gap =============================
    uint256[50] private _gap;
}
