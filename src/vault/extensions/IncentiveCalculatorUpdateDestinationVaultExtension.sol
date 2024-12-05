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
contract IncentiveCalculatorUpdateDestinationVaultExtension is BaseDestinationVaultExtension {
    error IncentiveCalculatorNotSet();

    event CalculatorUpdateExtensionExecuted(address newCalc, address oldCalc);

    /// @param slot The slot that the new calculator will be stored at
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
    function execute(
        bytes memory data
    ) external override onlyDestinationVault {
        IncentiveCalculatorUpdateParams memory params = abi.decode(data, (IncentiveCalculatorUpdateParams));
        uint256 slot = params.slot;
        address oldCalc = params.oldCalc;
        address newCalc = params.newCalc;

        // Slot can technically be 0, if newCalc is not zero by default oldCalc will revert when zero below
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
