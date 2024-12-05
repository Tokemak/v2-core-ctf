// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { StatsTransientCacheStore } from "src/stats/calculators/set/StatsTransientCacheStore.sol";

abstract contract TransientCacheStoreTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry internal systemRegistry;
    IAccessController internal accessController;

    StatsTransientCacheStore internal cache;

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() external {
        systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        accessController = IAccessController(makeAddr("accessController"));

        _mockSysRegAccessController(systemRegistry, address(accessController));

        cache = new StatsTransientCacheStore(systemRegistry);
    }

    function grantWriteRole() internal {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR, true);
    }

    function prohibitWriteRole() internal {
        _mockAccessControllerHasRole(accessController, address(this), Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR, false);
    }
}

contract Constructor is TransientCacheStoreTests {
    function test_SavesSystemRegistry() external {
        assertEq(cache.getSystemRegistry(), address(systemRegistry), "systemRegistry");
    }

    function test_SavesAccessController() external {
        assertEq(address(cache.accessController()), address(accessController), "accessController");
    }
}

contract GetTransient is TransientCacheStoreTests {
    function test_ReturnsDataWhenPresent() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(data[0], cache.getTransient(aprIds[0]), "aprId0");
    }

    function test_ReturnsEmptyDataWhenNotPresent() external {
        assertEq("", cache.getTransient(keccak256("aprId1")), "aprId0");
    }
}

contract HasTransient is TransientCacheStoreTests {
    function test_ReturnsTrueWhenDataPresent() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(true, cache.hasTransient(aprIds[0]), "aprId1");
    }

    function test_ReturnsFalseWhenDataEmpty() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(false, cache.hasTransient(aprIds[0]), "aprId0");
    }

    function test_ReturnsFalseWhenNotSet() external {
        assertEq(false, cache.hasTransient(keccak256("aprId1")), "aprId1");
    }
}

contract ClearTransient is TransientCacheStoreTests {
    function test_RevertIf_NotCalledByRole() external {
        prohibitWriteRole();

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        cache.clearTransient();
    }

    function test_ClearsSetData() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(data[0], cache.getTransient(aprIds[0]), "aprId0");

        cache.clearTransient();

        assertEq("", cache.getTransient(aprIds[0]), "clear");
    }

    function test_ClearsTrackedKeys() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(true, cache.hasTransient(bytes32(cache.SET_KEYS())), "set");

        cache.clearTransient();

        assertEq(false, cache.hasTransient(bytes32(cache.SET_KEYS())), "unset");
    }
}

contract WriteTransient is TransientCacheStoreTests {
    function test_RevertIf_NotCalledByRole() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        prohibitWriteRole();

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        cache.writeTransient(aprIds, data);

        grantWriteRole();

        cache.writeTransient(aprIds, data);
    }

    function test_RevertIf_NoDataPassed() external {
        bytes32[] memory aprIds = new bytes32[](0);
        bytes[] memory data = new bytes[](0);

        grantWriteRole();

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "len"));
        cache.writeTransient(aprIds, data);
    }

    function test_RevertIf_ArrayDataLengthMismatched() external {
        bytes32[] memory aprIds = new bytes32[](2);
        bytes[] memory data = new bytes[](1);

        grantWriteRole();

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, 2, 1, "arr"));
        cache.writeTransient(aprIds, data);
    }

    function test_RevertIf_AttemptingToOverwriteDataInCache() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        vm.expectRevert(abi.encodeWithSelector(StatsTransientCacheStore.DataExists.selector));
        cache.writeTransient(aprIds, data);
    }

    function test_RevertIf_AttemptingToSetProhibitedKey() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = bytes32(cache.SET_KEYS());

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        vm.expectRevert(abi.encodeWithSelector(StatsTransientCacheStore.InvalidKey.selector, aprIds[0]));
        cache.writeTransient(aprIds, data);

        aprIds[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(StatsTransientCacheStore.InvalidKey.selector, 0));
        cache.writeTransient(aprIds, data);
    }

    function test_SavesSingleEntry() external {
        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("aprId1");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode("data1");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(data[0], cache.getTransient(aprIds[0]), "aprId0");
    }

    function test_SavesMultipleEntries() external {
        bytes32[] memory aprIds = new bytes32[](2);
        aprIds[0] = keccak256("aprId1");
        aprIds[1] = keccak256("aprId2");

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode("data1");
        data[0] = abi.encode("data2");

        grantWriteRole();

        cache.writeTransient(aprIds, data);

        assertEq(data[0], cache.getTransient(aprIds[0]), "aprId0");
        assertEq(data[1], cache.getTransient(aprIds[1]), "aprId1");
    }
}
