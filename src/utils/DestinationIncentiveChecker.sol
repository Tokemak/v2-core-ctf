// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";

import { IAuraStashToken } from "src/interfaces/external/aura/IAuraStashToken.sol";
import { IConvexStashToken } from "src/interfaces/external/convex/IConvexStashToken.sol";

/// @title Checks for incentive tokens that are not registered
contract DestinationIncentiveChecker is SystemComponent {
    uint256 public constant VERSION = 1;

    bytes32 public constant BALANCER = keccak256("balancer");
    bytes32 public constant CURVE = keccak256("curve");

    constructor(ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) { }

    /// @notice Checks for unregistered incentive tokens across all destinations and returns them
    function check() external view returns (address[] memory) {
        // Get incentive tokens and destinations
        address[] memory registeredIncentiveTokens = systemRegistry.incentivePricing().getRegisteredTokens();
        address[] memory destinations = systemRegistry.destinationVaultRegistry().listVaults();

        address[] memory unregistered = new address[](type(uint128).max);
        uint256 unregisteredIndex = 0;
        // Loop through all destinations
        for (uint256 i = 0; i < destinations.length; ++i) {
            DestinationVault currentDest = DestinationVault(destinations[i]);
            bytes32 exchange = keccak256(abi.encodePacked(currentDest.exchangeName()));

            address[] memory toValidate;
            // If the exchange is either Balancer or Curve, get incentive tokens from that destination
            if (exchange == BALANCER) {
                toValidate = _handleBalancer(currentDest);
            } else if (exchange == CURVE) {
                toValidate = _handleCurve(currentDest);
            }

            // Loop through tokens to validate from destination and see if they are registered in incentives
            for (uint256 j = 0; j < toValidate.length; ++j) {
                address currentTokenToValidate = toValidate[j];

                // Take care of zero addresses that can be returned from `_handle` functions, skip this iteration
                if (currentTokenToValidate == address(0)) continue;

                for (uint256 k = 0; k < registeredIncentiveTokens.length; ++k) {
                    // If token to validate is equal to registered, break, don't need to do anything
                    if (currentTokenToValidate == registeredIncentiveTokens[k]) break;

                    // If we get to the end of the registered array, to validate is not there.  Add to unregistered
                    if (k == registeredIncentiveTokens.length - 1) {
                        unregistered[unregisteredIndex] = currentTokenToValidate;
                        unregisteredIndex++;
                    }
                }
            }
        }

        address[] memory toReturn = new address[](unregisteredIndex);
        // Remove zero addresses from the end of unregistered array for return
        for (uint256 i = 0; i < unregisteredIndex; ++i) {
            toReturn[i] = unregistered[i];
        }

        return toReturn;
    }

    /// @dev Handles getting tokens from a Balancer destination
    /// @return incentives Array of incentive tokens for destination, if any
    function _handleBalancer(DestinationVault dest) private view returns (address[] memory incentives) {
        // Get aura staking from destination
        // NOTE: Aura staking does not exist for all Balancer destination vaults
        (bool success, bytes memory retData) = address(dest).staticcall(abi.encodeWithSignature("auraStaking()"));
        if (!success || retData.length == 0) return incentives;
        IBaseRewardPool rewardPool = IBaseRewardPool(abi.decode(retData, (address)));

        uint256 extraRewardLength = rewardPool.extraRewardsLength();
        incentives = new address[](extraRewardLength - 1);

        address[] memory destTrackedTokens = dest.trackedTokens();

        for (uint256 i = 0; i < extraRewardLength; ++i) {
            // All extra reward tokens are stask tokens in Aura system
            IAuraStashToken stashToken =
                IAuraStashToken(address(IBaseRewardPool(rewardPool.extraRewards(i)).rewardToken()));
            if (stashToken.isValid()) {
                incentives[i] = stashToken.baseToken();
            }

            // Dest tracked tokens are not tracked via incentives but can be returned via rewarders in some cases.
            // Filter out to avoid false positives
            if (incentives[i] != address(0)) {
                for (uint256 j = 0; j < destTrackedTokens.length; ++j) {
                    if (incentives[i] == destTrackedTokens[j]) {
                        incentives[i] = address(0);
                    }
                }
            }
        }
    }

    /// @dev Handles getting tokens from a Curve destination
    /// @return incentives Array of incentive tokens for destination, if any
    function _handleCurve(DestinationVault dest) private view returns (address[] memory incentives) {
        // Get convex staking from destination vault
        (bool success, bytes memory retData) = address(dest).staticcall(abi.encodeWithSignature("convexStaking()"));
        if (!success || retData.length == 0) return incentives;
        IBaseRewardPool rewardPool = IBaseRewardPool(abi.decode(retData, (address)));

        uint256 extraRewardLength = rewardPool.extraRewardsLength();
        incentives = new address[](extraRewardLength - 1);

        address[] memory destTrackedTokens = dest.trackedTokens();

        for (uint256 i = 0; i < extraRewardLength; ++i) {
            address token = address(IBaseRewardPool(rewardPool.extraRewards(i)).rewardToken());

            // Check for stash token.  If we get a stash token get underlying incentive token
            (success, retData) = token.staticcall(abi.encodeCall(IConvexStashToken.token, ()));
            if (success && retData.length > 0) {
                (, bytes memory isInvalidData) = token.staticcall(abi.encodeCall(IConvexStashToken.isInvalid, ()));

                if (!abi.decode(isInvalidData, (bool))) {
                    incentives[i] = abi.decode(retData, (address));
                }
            } else {
                incentives[i] = token;
            }

            // Dest tracked tokens are not tracked via incentives but can be returned via rewarders in some cases.
            // Filter out to avoid false positives
            if (incentives[i] != address(0)) {
                for (uint256 j = 0; j < destTrackedTokens.length; ++j) {
                    if (incentives[i] == destTrackedTokens[j]) {
                        incentives[i] = address(0);
                    }
                }
            }
        }
    }
}
