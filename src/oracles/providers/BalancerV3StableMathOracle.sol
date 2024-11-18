// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVaultV3 } from "src/interfaces/external/balancer/IVaultV3.sol";
import { Errors } from "src/utils/Errors.sol";

import { PoolData } from "src/external/balancer/VaultTypes.sol";

import {
    BalancerBaseStableMathOracle, ISystemRegistry
} from "src/oracles/providers/base/BalancerBaseStableMathOracle.sol";

contract BalancerV3StableOracle is BalancerBaseStableMathOracle {
    IVaultV3 public immutable vault;

    struct BalancerV3StableOracleData {
        uint256[] currentLiveBalances;
        uint256[] decimalScalingFactors;
        uint256[] rateScalingFactors;
    }

    constructor(IVaultV3 _vault, ISystemRegistry _registry) BalancerBaseStableMathOracle(_registry) {
        Errors.verifyNotZero(address(_vault), "_vault");

        vault = _vault;
    }

    function getDescription() external pure override returns (string memory) {
        return "balV3StableMath";
    }

    function _getLiveBalancesAndScalingFactors(
        bytes memory data
    ) internal pure override returns (uint256[] memory liveBalances, uint256[] memory scalingFactors) {
        BalancerV3StableOracleData memory decodedData = abi.decode(data, (BalancerV3StableOracleData));
        liveBalances = decodedData.currentLiveBalances;

        uint256 len = liveBalances.length;
        for (uint256 i = 0; i < len; ++i) {
            scalingFactors[i] = decodedData.decimalScalingFactors[i] * decodedData.rateScalingFactors[i] / 1e18;
        }
    }

    function _getTotalSupply(
        address pool
    ) internal view override returns (uint256) {
        return IERC20(pool).totalSupply();
    }

    function _getPoolTokens(
        address pool
    ) internal view override returns (IERC20[] memory, uint256[] memory, bytes memory) {
        PoolData memory poolData = vault.getPoolData(pool);

        return (
            poolData.tokens,
            poolData.balancesRaw,
            abi.encode(
                BalancerV3StableOracleData({
                    currentLiveBalances: poolData.balancesLiveScaled18,
                    decimalScalingFactors: poolData.decimalScalingFactors,
                    rateScalingFactors: poolData.tokenRates
                })
            )
        );
    }
}
