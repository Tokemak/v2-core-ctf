// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IDestinationVaultExtension } from "src/interfaces/vault/IDestinationVaultExtension.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

/// @title A base DV extension with claim, swap and queue rewards functionality
/// @dev This contract is meant to be accessed in a delegatecall context
abstract contract BaseDestinationVaultExtension is SystemComponent, ReentrancyGuard, IDestinationVaultExtension {
    using Address for address;
    using SafeERC20 for IERC20;

    address public immutable asyncSwapper;
    IERC20 public immutable weth;

    /// @notice Thrown when an invalid amount of a token is received
    error InvalidAmountReceived(uint256 expected, uint256 received);

    /// @notice Emitted when an extension is executed
    /// @param amountsClaimed Amounts of reward tokens claimed
    /// @param tokensClaimed Addresses of tokens claimed
    /// @param amountAddedToRewards Total amount of all tokens added to rewards
    event ExtensionExecuted(uint256[] amountsClaimed, address[] tokensClaimed, uint256 amountAddedToRewards);

    /// @param sendToRewarder Send to DV rewarder if true. If false funds sent to msg.sender
    /// @param claimData Bytes data to be passed to and decoded in claim function
    /// @param swapParams Array of SwapParams structs, one per swap being made
    struct BaseExtensionParams {
        bool sendToRewarder;
        bytes claimData;
        SwapParams[] swapParams;
    }

    /// @dev address(this) will be the DVs address in a delegatecall context
    modifier onlyDestinationVault() {
        systemRegistry.destinationVaultRegistry().verifyIsRegistered(address(this));
        _;
    }

    // slither-disable-next-line similar-names
    constructor(ISystemRegistry _systemRegistry, address _asyncSwapper) SystemComponent(_systemRegistry) {
        _systemRegistry.asyncSwapperRegistry().verifyIsRegistered(_asyncSwapper);

        asyncSwapper = _asyncSwapper;
        weth = systemRegistry.weth();
    }

    /// @inheritdoc IDestinationVaultExtension
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
        // Send rewards to either message sender or rewarder
        //
        if (params.sendToRewarder) {
            address rewarder = IDestinationVault(address(this)).rewarder();
            LibAdapter._approve(weth, rewarder, amountReceived);
            IMainRewarder(rewarder).queueNewRewards(amountReceived);
        } else {
            weth.safeTransfer(msg.sender, amountReceived);
        }

        emit ExtensionExecuted(amountsClaimed, tokensClaimed, amountReceived);
    }

    /// @notice Used for inheriting contracts to implement custom claiming functionalities
    /// @dev Inheriting contract should implement necessary checks, this contract does not handle any checks for
    /// claiming
    function _claim(
        bytes memory data
    ) internal virtual returns (uint256[] memory amountClaimed, address[] memory tokensClaimed);
}
