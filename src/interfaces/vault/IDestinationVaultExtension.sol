// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IDestinationVaultExtension {
    function execute(
        bytes calldata data
    ) external;
}
