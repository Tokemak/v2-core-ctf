// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { SYSTEM_REGISTRY_MAINNET, TREASURY } from "test/utils/Addresses.sol";

import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IncentiveCalculatorUpdateDestinationVaultExtension } from
    "src/vault/extensions/IncentiveCalculatorUpdateDestinationVaultExtension.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";

//solhint-disable

contract IncentiveCalculatorUpdateDestinationVaultExtensionTest is Test {
    // Using DV stood up on mainnet to test.  Bal weEth / rEth pool
    IDestinationVault public constant dv = IDestinationVault(0x148Ca723BefeA7b021C399413b8b7426A4701500);
    ISystemRegistry public constant systemRegistry = ISystemRegistry(SYSTEM_REGISTRY_MAINNET);
    uint256 public constant SLOT = 10; // Slot where _incentiveCalc stored

    IncentiveCalculatorUpdateDestinationVaultExtension public extension;

    event CalculatorUpdateExtensionExecuted(address newCalc, address oldCalc);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_338_691);

        extension = new IncentiveCalculatorUpdateDestinationVaultExtension(systemRegistry);

        vm.startPrank(TREASURY);
        systemRegistry.accessController().setupRole(Roles.DESTINATION_VAULT_MANAGER, address(this));
        vm.stopPrank();

        dv.setExtension(address(extension));

        // Warp timestamp so extension can be executed
        vm.warp(block.timestamp + 7 days);
    }

    function _generateData(
        uint256 _slot,
        address _oldCalc,
        address _newCalc
    ) private pure returns (bytes memory data) {
        data = abi.encode(
            IncentiveCalculatorUpdateDestinationVaultExtension.IncentiveCalculatorUpdateParams({
                slot: _slot,
                oldCalc: _oldCalc,
                newCalc: _newCalc
            })
        );
    }

    function test_RevertIf_NoDelegatecall() public {
        bytes memory data = _generateData(0, address(1), address(1));

        // Call directly instead of through dv.  Dv uses delegatecall
        vm.expectRevert(Errors.NotRegistered.selector);
        extension.execute(data);
    }

    function test_RevertIf_NewCalculator_Zero() public {
        bytes memory data = _generateData(SLOT, address(dv.getStats()), address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newCalc"));
        dv.executeExtension(data);
    }

    function test_RevertIf_OldCalculator_Zero() public {
        bytes memory data = _generateData(SLOT, address(0), makeAddr("newCalc"));

        vm.expectRevert(IncentiveCalculatorUpdateDestinationVaultExtension.IncentiveCalculatorNotSet.selector);
        dv.executeExtension(data);
    }

    function test_RevertIf_SlotNotUpdated() public {
        // Data doesn't matter for this one, just want it to fail
        bytes memory data = _generateData(0, address(1), address(1));

        vm.expectRevert(IncentiveCalculatorUpdateDestinationVaultExtension.IncentiveCalculatorNotSet.selector);
        dv.executeExtension(data);
    }

    function test_RunsProperly_EmitsEvent() public {
        address currentCalc = address(dv.getStats());
        address newCalc = makeAddr("newCalc");

        bytes memory data = _generateData(SLOT, currentCalc, newCalc);

        vm.expectEmit(true, true, true, true);
        emit CalculatorUpdateExtensionExecuted(newCalc, currentCalc);
        dv.executeExtension(data);

        assertEq(address(dv.getStats()), newCalc);
    }
}
