// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMultiOnesOracle {
    function isAssetActive(address token) external view returns (bool);
    
    function getPriceSafe(
        address token, 
        uint256 maxTimeDelay
    ) external view returns (uint256 price, uint256 delay);

    function getLatestRoundData(
        address token
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);

    function getRoundData(
        address token, 
        uint80 _roundId
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);

    function getPriceAtTime(
        address token, 
        uint256 timestamp
    ) external view returns (uint80 roundId, uint256 price, uint256 updatedAt);
}
