// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice Interface for a deployed CustomSetOracle to access its prices and setPrices function
interface ICustomOracle {
    struct Price {
        uint192 price;
        uint32 maxAge;
        uint32 timestamp;
    }

    function accessController() external view returns (address);

    /// @notice Get the price of one of the registered tokens from prices mapping in CustomSetOracle
    function prices(
        address token
    ) external view returns (Price memory);

    /// @dev Access to the CustomSetOracle contract to set prices
    function setPrices(
        address[] memory tokens,
        uint256[] memory ethPrices,
        uint256[] memory queriedTimestamps
    ) external;

    function registerTokens(address[] memory tokens, uint256[] memory maxAges) external;

    function isRegistered(
        address token
    ) external view returns (bool);

    function maxAge() external view returns (uint256);
}
