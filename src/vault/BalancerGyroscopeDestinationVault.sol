// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { IDestinationVault } from "src/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { IBalancerGyroPool } from "src/interfaces/external/balancer/IBalancerGyroPool.sol";

/// @title Destination Vault to proxy a Balancer Pool that goes into Gyroscope
contract BalancerGyroscopeDestinationVault is BalancerAuraDestinationVault {
    constructor(
        ISystemRegistry sysRegistry,
        address _balancerVault,
        address _defaultStakingRewardToken
    ) BalancerAuraDestinationVault(sysRegistry, _balancerVault, _defaultStakingRewardToken) { }

    /// @inheritdoc IDestinationVault
    function poolType() external pure override returns (string memory) {
        return "balGyro";
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view override returns (uint256) {
        return IBalancerGyroPool(_underlying).getActualSupply();
    }

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view override returns (address[] memory ret) {
        ret = BalancerUtilities._convertERC20sToAddresses(poolTokens);
    }
}
