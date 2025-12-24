// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMultiOnesOracle
/// @notice Interface for the MultiOnesOracle contract
interface IMultiOnesOracle {
    /// @notice Checks if an asset is active
    function isAssetActive(address token) external view returns (bool);
    
    /// @notice Retrieves the current price of an asset, ensuring it's not stale
    function getPriceSafe(
        address token, 
        uint256 maxTimeDelay
    ) external view returns (uint256 price, uint256 delay);

    /// @notice Retrieves the latest round data for an asset
    function getLatestRoundData(
        address token
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);

    /// @notice Retrieves historical round data for an asset
    function getRoundData(
        address token, 
        uint80 _roundId
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);

    /// @notice Retrieves the price of an asset at a specific timestamp (binary search)
    function getPriceAtTime(
        address token, 
        uint256 timestamp
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);
}
