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

    function test_EnsureCalcsCannotBeZero() public {
        address newCalc = makeAddr("newCalc");

        // Test old is zero
        bytes memory data = _generateData(10, address(0), newCalc);

        // Reverts when oldCalc != calc registered to DV
        vm.expectRevert(Errors.InvalidConfiguration.selector);
        dv.executeExtension(data);

        // Test new is zero
        data = _generateData(10, address(dv.getStats()), address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newCalc"));
        dv.executeExtension(data);

        // Test both are zero
        data = _generateData(10, address(0), address(0));

        // Will still be caught by zero address check for new calculator
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newCalc"));
        dv.executeExtension(data);
    }

    function test_RevertIf_CalcsMatch() public {
        bytes memory data = _generateData(10, address(1), address(1));

        vm.expectRevert(IncentiveCalculatorUpdateDestinationVaultExtension.CalculatorsMatch.selector);
        dv.executeExtension(data);
    }

    function test_RevertIf_getStatsCallBeforeUpdate_DoesNotEqual_OldCalc() public {
        // Dv registered calc will be 0x8CCCdB904b79F22E1d7f2BFa0638fB6F8b3e6A1C
        bytes memory data = _generateData(10, address(1), makeAddr("newCalc"));

        vm.expectRevert(Errors.InvalidConfiguration.selector);
        dv.executeExtension(data);
    }

    function test_RevertIf_getStatsCallAfterUpdate_DoesNotEqual_NewCalc() public {
        bytes memory data = _generateData(10, address(dv.getStats()), makeAddr("newCalc"));

        // Have to mock call for this one
        vm.mockCall(address(dv), abi.encodeWithSignature("getStats()"), abi.encode(address(1)));

        vm.expectRevert(Errors.InvalidConfiguration.selector);
        dv.executeExtension(data);
    }

    // Will revert in same fashion as above
    function test_RevertIf_SlotIncorrect() public {
        // Because slot is incorrect, slot val will not load from storage correctly and will force a revert when
        // checking
        // dv.getStats() vs newCalc
        bytes memory data = _generateData(1, address(dv.getStats()), makeAddr("newCalc"));

        vm.expectRevert(Errors.InvalidConfiguration.selector);
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
