// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

/// @title Swaps tokens for weth on Tokemak controlled "bank" multisig to avoid high slippage swaps on illiq∫uid markets
/// @dev Designed to interact with Tokemak controlled contract.  Forgoes some checks necessary for external contracts
contract BankSwapper is IAsyncSwapper, SystemComponent {
    address public immutable BANK;

    // address(this) will be LiquidationRow contract in delegatecall context
    modifier onlyLiquidator() {
        if (!systemRegistry.accessController().hasRole(Roles.BANK_SWAP_MANAGER, address(this))) {
            revert Errors.AccessDenied();
        }
        _;
    }

    constructor(address _bank, ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(_bank, "_bank");

        BANK = _bank;
    }

    /// @inheritdoc IAsyncSwapper
    function swap(
        SwapParams memory swapParams
    ) external onlyLiquidator returns (uint256 buyTokenAmountReceived) {
        IERC20 sellToken = IERC20(swapParams.sellTokenAddress);
        IERC20 buyToken = IERC20(swapParams.buyTokenAddress);
        uint256 sellAmount = swapParams.sellAmount;
        buyTokenAmountReceived = swapParams.buyAmount;

        if (address(sellToken) == address(0)) revert TokenAddressZero();
        if (address(buyToken) == address(0)) revert TokenAddressZero();
        if (sellAmount == 0) revert InsufficientSellAmount();
        if (buyTokenAmountReceived == 0) revert InsufficientBuyAmount();

        // Transfers
        uint256 sellTokenBalance = sellToken.balanceOf(address(this));
        if (sellTokenBalance < sellAmount) revert InsufficientBalance(sellTokenBalance, sellAmount);
        if (buyToken.balanceOf(BANK) < buyTokenAmountReceived) revert SwapFailed();

        sellToken.transfer(BANK, sellAmount);
        buyToken.transferFrom(BANK, address(this), buyTokenAmountReceived);

        emit Swapped(address(sellToken), address(buyToken), sellAmount, buyTokenAmountReceived, buyTokenAmountReceived);

        return buyTokenAmountReceived;
    }
}
