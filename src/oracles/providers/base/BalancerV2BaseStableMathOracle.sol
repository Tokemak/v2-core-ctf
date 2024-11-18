// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IBasePool } from "src/interfaces/external/balancer/IBasePool.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";

import { ScalingHelpers } from "src/external/balancer/ScalingHelpers.sol";

import {
    BalancerBaseStableMathOracle, ISystemRegistry
} from "src/oracles/providers/base/BalancerBaseStableMathOracle.sol";

/// @notice Contains common functionality between MetaStable and ComposableStable pool oracles
abstract contract BalancerV2BaseStableMathOracle is BalancerBaseStableMathOracle {
    IVault public immutable vault;

    struct BalancerV2StableOracleData {
        address pool;
        uint256[] rawBalances;
    }

    constructor(IVault _vault, ISystemRegistry _registry) BalancerBaseStableMathOracle(_registry) {
        vault = _vault;
    }

    function _getLiveBalancesAndScalingFactors(
        bytes memory data
    ) internal view override returns (uint256[] memory scaledBalances, uint256[] memory scalingFactors) {
        BalancerV2StableOracleData memory decodedData = abi.decode(data, (BalancerV2StableOracleData));

        scalingFactors = IBasePool(decodedData.pool).getScalingFactors();

        uint256[] memory rawBalances = decodedData.rawBalances;
        uint256 length = rawBalances.length;

        // TODO: Can likely change this to array function
        for (uint256 i = 0; i < length; ++i) {
            scaledBalances[i] = ScalingHelpers.toScaled18RoundDown(rawBalances[i], scalingFactors[i]);
        }
    }
}
