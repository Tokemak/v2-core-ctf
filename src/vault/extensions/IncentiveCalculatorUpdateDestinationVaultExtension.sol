// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import {
    BaseDestinationVaultExtension,
    IDestinationVaultExtension
} from "src/vault/extensions/base/BaseDestinationVaultExtension.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { Errors } from "src/utils/Errors.sol";

// solhint-disable no-inline-assembly

/// @title An extension to replace _incentiveCalculator on a destination vault
/// @dev This contract can only be accessed in a delegatecall context
contract IncentiveCalculatorUpdateDestinationVaultExtension is BaseDestinationVaultExtension {
    /// @notice Thrown when a calculator is not update
    error IncentiveCalculatorNotSet();

    /// @notice Emitted when an extension is updated
    event CalculatorUpdateExtensionExecuted(address newCalc, address oldCalc);

    /// @param slot Storage slot for DV._incentiveCalculator.  Find using evm.storage
    /// @param oldCalc The address of the old calculator
    /// @param newCalc The address of the new calculator
    struct IncentiveCalculatorUpdateParams {
        uint256 slot;
        address oldCalc;
        address newCalc;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseDestinationVaultExtension(_systemRegistry) { }

    /// @inheritdoc IDestinationVaultExtension
    /// @dev Use evm.storage and the address of the DV you are looking to replace the calculator for to get the slot
    /// @dev oldCalc can be retrieved using DestinationVault.getStats()
    function execute(
        bytes memory data
    ) external override onlyDestinationVault {
        IncentiveCalculatorUpdateParams memory params = abi.decode(data, (IncentiveCalculatorUpdateParams));
        uint256 slot = params.slot;
        address oldCalc = params.oldCalc;
        address newCalc = params.newCalc;

        // Slot can technically be 0, if newCalc is not zero by default oldCalc by default when zero on check below
        Errors.verifyNotZero(newCalc, "newCalc");

        bool set = false;
        address slotVal;
        assembly {
            slotVal := sload(slot)

            if eq(slotVal, oldCalc) {
                sstore(slot, newCalc)
                set := true
            }
        }

        if (!set) {
            revert IncentiveCalculatorNotSet();
        }

        emit CalculatorUpdateExtensionExecuted(newCalc, oldCalc);
    }
}
