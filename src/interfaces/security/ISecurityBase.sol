// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAccessController } from "src/interfaces/security/IAccessController.sol";

interface ISecurityBase {
    /// @notice Returns the address of the access controller
    /// @return Address of the access controller
    function accessController() external view returns (IAccessController);
}
