// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { BaseSetCalculator } from "src/stats/calculators/set/BaseSetCalculator.sol";
import { DexIncentiveSetCalculator } from "src/stats/calculators/set/DexIncentiveSetCalculator.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { VmSafe } from "forge-std/Vm.sol";

abstract contract DexIncentiveSetCalculatorTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry internal systemRegistry;
    IAccessController internal accessController;

    DexIncentiveSetCalculator internal calculator;

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() external {
        systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        accessController = IAccessController(makeAddr("accessController"));

        _mockSysRegAccessController(systemRegistry, address(accessController));

        calculator = DexIncentiveSetCalculator(Clones.clone(address(new DexIncentiveSetCalculator(systemRegistry))));
    }

    function getDefaultInitData() internal returns (BaseSetCalculator.InitData memory) {
        address[] memory baseCalculators = new address[](1);
        baseCalculators[0] = makeAddr("baseCalculator");
        return BaseSetCalculator.InitData({
            addressId: makeAddr("addressId"),
            baseCalculators: baseCalculators,
            cacheStore: makeAddr("cacheStore"),
            aprId: keccak256("aprId"),
            calcType: "base"
        });
    }
}

contract Initialize is DexIncentiveSetCalculatorTests {
    function test_SavesInitializationData() external {
        BaseSetCalculator.InitData memory initData = getDefaultInitData();
        _mockSystemComponent(systemRegistry, initData.cacheStore);
        calculator.initialize(new bytes32[](0), abi.encode(initData));

        assertEq(calculator.getAddressId(), initData.addressId, "addressId");
        assertEq(calculator.baseCalculators().length, initData.baseCalculators.length, "baseCalculator");
        for (uint256 i = 0; i < calculator.baseCalculators().length; i++) {
            assertEq(
                calculator.baseCalculators()[i],
                initData.baseCalculators[i],
                string.concat("baseCalculators", string(abi.encodePacked(i)))
            );
        }
        assertEq(address(calculator.cacheStore()), initData.cacheStore, "cacheStore");
        assertEq(calculator.getAprId(), initData.aprId, "aprId");
        assertEq(calculator.calcType(), initData.calcType, "calcType");
    }

    function test_RevertIf_CacheStoreRegistryDoesntMatch() external {
        BaseSetCalculator.InitData memory initData = getDefaultInitData();
        _mockSystemComponent(ISystemRegistry(makeAddr("badRegistry")), initData.cacheStore);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.SystemMismatch.selector, address(systemRegistry), makeAddr("badRegistry"))
        );
        calculator.initialize(new bytes32[](0), abi.encode(initData));
    }

    function test_RevertIf_AlreadyInitialized() external {
        BaseSetCalculator.InitData memory initData = getDefaultInitData();
        _mockSystemComponent(systemRegistry, initData.cacheStore);
        calculator.initialize(new bytes32[](0), abi.encode(initData));

        vm.expectRevert("Initializable: contract is already initialized");
        calculator.initialize(new bytes32[](0), abi.encode(initData));
    }

    function test_RevertIf_TemplateContract() external {
        BaseSetCalculator.InitData memory initData = getDefaultInitData();
        _mockSystemComponent(systemRegistry, initData.cacheStore);
        BaseSetCalculator localCalc = new DexIncentiveSetCalculator(systemRegistry);

        vm.expectRevert("Initializable: contract is already initialized");
        localCalc.initialize(new bytes32[](0), abi.encode(initData));
    }
}

contract ShouldSnapshot is DexIncentiveSetCalculatorTests {
    function test_ReturnsFalse() external {
        assertEq(calculator.shouldSnapshot(), false, "val");
    }
}

contract Snapshot is DexIncentiveSetCalculatorTests {
    function test_IsNoOp() external {
        BaseSetCalculator.InitData memory initData = getDefaultInitData();
        _mockSystemComponent(systemRegistry, initData.cacheStore);
        calculator.initialize(new bytes32[](0), abi.encode(initData));

        vm.startStateDiffRecording();
        calculator.snapshot();
        VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();
        _ensureNoStateChanges(records);
    }

    function _ensureNoStateChanges(
        VmSafe.AccountAccess[] memory records
    ) internal {
        for (uint256 i = 0; i < records.length; i++) {
            if (!records[i].reverted) {
                assertEq(records[i].oldBalance, records[i].newBalance);
                assertEq(records[i].deployedCode.length, 0);

                for (uint256 s = 0; s < records[i].storageAccesses.length; s++) {
                    if (records[i].storageAccesses[s].isWrite) {
                        if (!records[i].storageAccesses[s].reverted) {
                            assertEq(
                                records[i].storageAccesses[s].previousValue, records[i].storageAccesses[s].newValue
                            );
                        }
                    }
                }
            }
        }
    }
}
