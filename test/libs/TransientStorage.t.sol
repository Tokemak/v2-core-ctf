// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TransientStorage } from "src/libs/TransientStorage.sol";

contract TransientStorageTest is Test {
    function testSetTransientStorage() public {
        bytes memory shortData = bytes(string("cc"));
        bytes memory longData = bytes(string("ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"));

        assertFalse(TransientStorage.dataExists(100));
        TransientStorage.setBytes(shortData, 100);

        assertFalse(TransientStorage.dataExists(1000));
        TransientStorage.setBytes(longData, 1000);

        assertTrue(TransientStorage.dataExists(100));
        assertTrue(TransientStorage.dataExists(1000));

        bytes memory newShortData = TransientStorage.getBytes(100);
        bytes memory newLongData = TransientStorage.getBytes(1000);

        assertEq(keccak256(shortData), keccak256(newShortData));
        assertEq(keccak256(longData), keccak256(newLongData));

        assertTrue(TransientStorage.dataExists(100));
        assertTrue(TransientStorage.dataExists(1000));

        TransientStorage.clearBytes(100);
        assertFalse(TransientStorage.dataExists(100));

        TransientStorage.clearBytes(1000);
        assertFalse(TransientStorage.dataExists(1000));
    }
}
