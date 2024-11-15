// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { ISwapRouterV2 } from "src/interfaces/swapper/ISwapRouterV2.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { TransientStorage } from "src/libs/TransientStorage.sol";
import { Errors } from "src/utils/Errors.sol";

contract SwapRouterV2 is ISwapRouterV2, SwapRouter {
    using SafeERC20 for IERC20;

    uint256 private constant _ROUTES = uint256(keccak256(bytes("ROUTES"))) - 1;
    uint256 private constant _CURRENT_SWAP_INDEX = uint256(keccak256(bytes("CURRENT_SWAP_INDEX"))) - 1;

    constructor(
        ISystemRegistry _systemRegistry
    ) SwapRouter(_systemRegistry) { }

    /// @inheritdoc ISwapRouter
    function swapForQuote(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount
    ) public override(SwapRouter, ISwapRouter) onlyDestinationVault(msg.sender) nonReentrant returns (uint256) {
        if (!_transientRoutesAvailable()) {
            return _swapForQuote(assetToken, sellAmount, quoteToken, minBuyAmount);
        }
        // if no transient -> use swapRoutes
        // if transient + empty route -> use swapRputes
        // if transient + non-empty route -> use transient
        // if transient + index out of bounds -> revert

        // maintain txn index
        uint256 index = _getCurrentSwapIndex();
        _setCurrentSwapIndex(index + 1);
        ISwapRouterV2.UserSwapData[] memory transientRoutes = _getTransientRoutes();
        if (index >= transientRoutes.length) revert InvalidParams();

        ISwapRouterV2.UserSwapData memory route = transientRoutes[index];
        if (route.target == address(0)) {
            return _swapForQuote(assetToken, sellAmount, quoteToken, minBuyAmount);
        } else {
            _validateSwapParams(assetToken, sellAmount, quoteToken);
            return _swapForQuoteUserRoute(assetToken, sellAmount, quoteToken, minBuyAmount, route);
        }
    }

    function _swapForQuoteUserRoute(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount,
        ISwapRouterV2.UserSwapData memory transientRoute
    ) internal returns (uint256) {
        if (transientRoute.fromToken != assetToken || transientRoute.toToken != quoteToken) {
            revert InvalidConfiguration();
        }

        uint256 balanceDiff = IERC20(quoteToken).balanceOf(address(this));
        IERC20(assetToken).safeTransferFrom(msg.sender, transientRoute.target, sellAmount);

        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = transientRoute.target.call(transientRoute.data);
        // slither-disable-end low-level-calls
        if (!success) revert SwapFailed();

        balanceDiff = IERC20(quoteToken).balanceOf(address(this)) - balanceDiff;
        if (balanceDiff < minBuyAmount) revert MaxSlippageExceeded();

        IERC20(quoteToken).safeTransfer(msg.sender, balanceDiff);
        emit SwapForQuoteSuccessful(assetToken, sellAmount, quoteToken, minBuyAmount, balanceDiff);
        return balanceDiff;
    }

    function _validateSwapParams(address assetToken, uint256 sellAmount, address quoteToken) internal pure {
        if (sellAmount == 0) revert Errors.ZeroAmount();
        if (assetToken == quoteToken) revert InvalidParams();
        Errors.verifyNotZero(assetToken, "assetToken");
        Errors.verifyNotZero(quoteToken, "quoteToken");
    }

    function initTransientSwap(
        ISwapRouterV2.UserSwapData[] memory customRoutes
    ) public onlyAutoPilotRouter {
        if (_transientRoutesAvailable()) revert AccessDenied();
        TransientStorage.setBytes(abi.encode(customRoutes), _ROUTES);
        TransientStorage.setBytes(abi.encode(0), _CURRENT_SWAP_INDEX); // probably not needed but
    }

    function exitTransientSwap() public onlyAutoPilotRouter {
        TransientStorage.clearBytes(_ROUTES);
        TransientStorage.clearBytes(_CURRENT_SWAP_INDEX);
    }

    function _setCurrentSwapIndex(
        uint256 index
    ) internal {
        TransientStorage.setBytes(abi.encode(index), _CURRENT_SWAP_INDEX);
    }

    function _getCurrentSwapIndex() internal view returns (uint256) {
        bytes memory indexEncoded = TransientStorage.getBytes(_CURRENT_SWAP_INDEX);
        return abi.decode(indexEncoded, (uint256));
    }

    function _getTransientRoutes() internal view returns (UserSwapData[] memory customRoutes) {
        bytes memory customRoutesEncoded = TransientStorage.getBytes(_ROUTES);
        customRoutes = abi.decode(customRoutesEncoded, (UserSwapData[]));
    }

    function _transientRoutesAvailable() internal view returns (bool) {
        return TransientStorage.dataExists(_ROUTES);
    }

    modifier onlyAutoPilotRouter() {
        if (msg.sender != address(systemRegistry.autoPoolRouter())) revert AccessDenied();
        _;
    }
}
