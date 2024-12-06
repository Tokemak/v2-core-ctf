// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseTest } from "test/BaseTest.t.sol";
import { SwapRouterV2 } from "src/swapper/SwapRouterV2.sol";
import { IDestinationVaultRegistry, DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISwapRouterV2 } from "src/swapper/SwapRouterV2.sol";
import { WETH_MAINNET, FRXETH_MAINNET, STETH_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
// solhint-disable max-line-length
contract SwapRouterV2Test is BaseTest {
    SwapRouterV2 private swapRouterV2;
    // SystemRegistry private systemRegistry;
    // AccessController private accessController;
    // DestinationVaultRegistry private destinationVaultRegistry;

    function setUp() public override {
        super.setUp();

        // setup system
        // systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        // accessController = new AccessController(address(systemRegistry));
        // systemRegistry.setAccessController(address(accessController));
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);

        // accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, address(this));

        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        swapRouterV2 = new SwapRouterV2(systemRegistry);
    }

    //Test Regular Swap For Quote incovations with new SwapRouterV2
    function test_swapForQuote_Revert_IfAccessDenied() public {
        uint256 sellAmount = 1e18;
        address asset = WETH_MAINNET;
        address quote = FRXETH_MAINNET;
        vm.mockCall(
            address(destinationVaultRegistry),
            abi.encodeWithSelector(IDestinationVaultRegistry.isRegistered.selector),
            abi.encode(false)
        );

        vm.expectRevert(Errors.AccessDenied.selector);
        swapRouterV2.swapForQuote(asset, sellAmount, quote, 1);
    }

    function test_swapForQuote_Revert_IfZeroAmount() public {
        address asset = WETH_MAINNET;
        address quote = STETH_MAINNET;

        vm.mockCall(
            address(destinationVaultRegistry),
            abi.encodeWithSelector(IDestinationVaultRegistry.isRegistered.selector),
            abi.encode(true)
        );

        vm.expectRevert(Errors.ZeroAmount.selector);
        swapRouterV2.swapForQuote(asset, 0, quote, 1);
    }

    function test_swapForQuote_Revert_IfSameTokens() public {
        address asset = WETH_MAINNET;

        vm.mockCall(
            address(destinationVaultRegistry),
            abi.encodeWithSelector(IDestinationVaultRegistry.isRegistered.selector),
            abi.encode(true)
        );

        vm.expectRevert(Errors.InvalidParams.selector);
        swapRouterV2.swapForQuote(asset, 1, asset, 1);
    }

    function test_initAndExitTransientSwap_RevertIfNotAutopilotRouter() public {
        ISwapRouterV2.UserSwapData[] memory swapRoutes = new ISwapRouterV2.UserSwapData[](2);

        for (uint256 i = 0; i < swapRoutes.length; i++) {
            swapRoutes[i] = ISwapRouterV2.UserSwapData({
                fromToken: address(0),
                toToken: address(0),
                target: address(0),
                data: bytes("")
            });
        }

        vm.expectRevert(Errors.AccessDenied.selector);
        swapRouterV2.initTransientSwap(swapRoutes);

        vm.startPrank(address(autoPoolRouter));
        swapRouterV2.initTransientSwap(swapRoutes);

        vm.stopPrank();
        vm.expectRevert(Errors.AccessDenied.selector);
        swapRouterV2.exitTransientSwap();
    }

    function test_initTransientAndExitSwapByAutopilotRouter() public {
        vm.startPrank(address(autoPoolRouter));

        ISwapRouterV2.UserSwapData[] memory swapRoutes = new ISwapRouterV2.UserSwapData[](2);

        for (uint256 i = 0; i < swapRoutes.length; i++) {
            swapRoutes[i] = ISwapRouterV2.UserSwapData({
                fromToken: address(0),
                toToken: address(0),
                target: address(0),
                data: bytes("")
            });
        }

        swapRouterV2.initTransientSwap(swapRoutes);

        swapRouterV2.exitTransientSwap();

        vm.stopPrank();
    }
}
