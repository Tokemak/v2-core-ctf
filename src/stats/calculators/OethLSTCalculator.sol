// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IOEth } from "src/interfaces/external/origin/IOEth.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";

contract OethLSTCalculator is LSTCalculatorBase {
    constructor(ISystemRegistry _systemRegistry) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return 1e36 / IOEth(lstTokenAddress).rebasingCreditsPerToken();
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return true;
    }
}
