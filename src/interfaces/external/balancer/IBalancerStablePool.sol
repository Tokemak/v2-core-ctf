// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @dev This interface is currently used for BalV2 and V3 stable pools, all have the same signature for this function
interface IBalancerStablePool {
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision);
}
