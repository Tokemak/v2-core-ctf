// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

//
//                   ▓▓
//                   ▓▓
//                   ▓▓
//                   ▓▓
//                   ▓▓
//       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓
//                                 ▓▓

import { Errors } from "src/utils/Errors.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistryBase } from "src/SystemRegistryBase.sol";

// solhint-disable max-states-count

/// @notice Root contract of the system instance on L2.
/// @dev All contracts in this instance of the system should be reachable from this contract
contract SystemRegistryL2 is SystemRegistryBase {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice TOKE token
    IERC20Metadata public toke;

    /// =====================================================
    /// Events
    /// =====================================================

    event TokeSet(address newAddress);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(address _toke, address _weth) SystemRegistryBase(_weth) {
        Errors.verifyNotZero(address(_toke), "_toke");

        toke = IERC20Metadata(_toke);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Set the Toke for this instance of the system
    /// @param newToke Address of the Toke contract
    function setToke(address newToke) external onlyOwner {
        Errors.verifyNotZero(newToke, "newToke");

        if (address(toke) == newToke) {
            revert DuplicateSet(newToke);
        }

        toke = IERC20Metadata(newToke);

        emit TokeSet(newToke);

        _verifySystemsAgree(address(newToke));
    }
}
