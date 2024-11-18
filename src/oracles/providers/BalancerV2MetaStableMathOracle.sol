// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";

import {
    BalancerV2BaseStableMathOracle,
    ISystemRegistry,
    IVault
} from "src/oracles/providers/base/BalancerV2BaseStableMathOracle.sol";

contract BalancerV2MetaStableMathOracle is BalancerV2BaseStableMathOracle {
    function getDescription() external pure override returns (string memory) {
        return "balV2MetaStable";
    }

    constructor(IVault _vault, ISystemRegistry _registry) BalancerV2BaseStableMathOracle(_vault, _registry) { }

    function _getTotalSupply(
        address pool
    ) internal view override returns (uint256) {
        return IERC20(pool).totalSupply();
    }

    // Get tokens through vault
    function _getPoolTokens(
        address pool
    )
        internal
        view
        override
        returns (IERC20[] memory poolTokens, uint256[] memory rawBalances, bytes memory extraData)
    {
        (poolTokens, rawBalances) = BalancerUtilities._getPoolTokens(vault, pool);
        extraData = abi.encode(BalancerV2StableOracleData({ pool: pool, rawBalances: rawBalances }));
    }
}
