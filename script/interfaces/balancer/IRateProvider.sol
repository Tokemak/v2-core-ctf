// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IRateProvider {
    /// @dev Returns rate
    function getRate() external view returns (uint256);
}
