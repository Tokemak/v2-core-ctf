// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { RedstoneConsumerNumericMock } from "redstone-finance/mocks/RedstoneConsumerNumericMock.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemComponent } from "src/SystemComponent.sol";

contract CustomRedStoneOracleAdapter is RedstoneConsumerNumericMock, SystemComponent {
    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    // Extract and validate the price from the redstone payload
    function extractPriceWithFeedId(bytes32 feedId) public view returns (uint256) {
        return getOracleNumericValueFromTxMsg(feedId);
    }

    // TODO: Add function to call custom oracle setPrices()
}
