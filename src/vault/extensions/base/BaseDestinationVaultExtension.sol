// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IDestinationVaultExtension } from "src/interfaces/vault/IDestinationVaultExtension.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

abstract contract BaseDestinationVaultExtension is SystemComponent, ReentrancyGuard, IDestinationVaultExtension {
    using Address for address;

    address public immutable asyncSwapper;
    IERC20 public immutable weth;

    error InvalidAmountReceived(uint256 expected, uint256 received);

    event ExtensionExecuted(uint256[] amountsClaimed, address[] tokensClaimed, uint256 amountAddedToRewards);

    struct BaseExtensionParams {
        bytes claimData;
        SwapParams[] swapParams;
    }

    // address(this) will be the DVs address in a delegatecall context
    modifier onlyDestinationVault() {
        systemRegistry.destinationVaultRegistry().verifyIsRegistered(address(this));
        _;
    }

    constructor(ISystemRegistry _systemRegistry, address _asyncSwapper) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(_asyncSwapper, "_asyncSwapper");

        asyncSwapper = _asyncSwapper;
        weth = systemRegistry.weth();
    }

    function execute(
        bytes calldata data
    ) external onlyDestinationVault nonReentrant {
        BaseExtensionParams memory params = abi.decode(data, (BaseExtensionParams));

        SwapParams[] memory swapParams = params.swapParams;
        uint256 swapParamsLength = swapParams.length;
        Errors.verifyNotZero(swapParamsLength, "swapParamsLength");

        //
        // Claim rewards
        //
        (uint256[] memory amountsClaimed, address[] memory tokensClaimed) = _claim(params.claimData);

        //
        // Swap for reward token
        //
        uint256 amountReceived;
        for (uint256 i = 0; i < swapParamsLength; ++i) {
            // Validations on swapData, amount returned, etc are being done in the `BaseAsyncSwapper` level
            // solhint-disable-next-line max-line-length
            bytes memory swapData = asyncSwapper.functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, swapParams[i]));
            amountReceived += abi.decode(swapData, (uint256));
        }

        //
        // Add rewards to DV rewarder
        //
        address rewarder = IDestinationVault(address(this)).rewarder();
        LibAdapter._approve(weth, rewarder, amountReceived);
        IMainRewarder(rewarder).queueNewRewards(amountReceived);

        emit ExtensionExecuted(amountsClaimed, tokensClaimed, amountReceived);
    }

    function _claim(
        bytes memory data
    ) internal virtual returns (uint256[] memory amountClaimed, address[] memory tokensClaimed);
}
