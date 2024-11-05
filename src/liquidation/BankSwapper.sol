// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

/// @title Swaps tokens on Tokemak controlled "bank" multisig to avoid high slippage swaps on illiquid markets
/// @dev WARNING!! Do NOT use this contract with a non Tokemak controlled contract.  This contract forgoes some
/// necessary checks for interacting with external contracts
/// @dev In addition to the above, this should only be used via the LiquidationRow.sol contract.  This contract performs
/// pricing checks to ensure the execution we are getting is within some margin
contract BankSwapper is IAsyncSwapper, SystemComponent {
    /// @notice Address of the bank contract
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

        // slither-disable-next-line missing-zero-check
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

        uint256 sellTokenBalance = sellToken.balanceOf(address(this));
        if (sellTokenBalance < sellAmount) revert InsufficientBalance(sellTokenBalance, sellAmount);
        if (buyToken.balanceOf(BANK) < buyTokenAmountReceived) revert SwapFailed();

        // slither-disable-start unchecked-transfer
        sellToken.transfer(BANK, sellAmount);
        // slither-disable-next-line arbitrary-send-erc20
        buyToken.transferFrom(BANK, address(this), buyTokenAmountReceived);
        // slither-disable-end unchecked-transfer

        // slither-disable-next-line reentrancy-events
        emit Swapped(address(sellToken), address(buyToken), sellAmount, buyTokenAmountReceived, buyTokenAmountReceived);
    }
}
