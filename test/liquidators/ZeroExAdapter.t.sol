// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BaseAsyncSwapper } from "../../src/liquidation/BaseAsyncSwapper.sol";
import { IAsyncSwapper, SwapParams } from "../../src/interfaces/liquidation/IAsyncSwapper.sol";
import { ZERO_EX_MAINNET, PRANK_ADDRESS, CVX_MAINNET, WETH_MAINNET } from "../utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract ZeroExAdapterTest is Test {
    BaseAsyncSwapper private adapter;

    function setUp() public {
        string memory endpoint = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint, 16_731_638);
        vm.selectFork(forkId);

        adapter = new BaseAsyncSwapper(ZERO_EX_MAINNET);
    }

    function test_Revert_IfBuyTokenAddressIsZeroAddress() public {
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 0, address(0), 0, new bytes(0), new bytes(0), block.timestamp));
    }

    function test_Revert_IfSellTokenAddressIsZeroAddress() public {
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        adapter.swap(SwapParams(address(0), 0, PRANK_ADDRESS, 1, new bytes(0), new bytes(0), block.timestamp));
    }

    function test_Revert_IfSellAmountIsZero() public {
        vm.expectRevert(IAsyncSwapper.InsufficientSellAmount.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 0, PRANK_ADDRESS, 1, new bytes(0), new bytes(0), block.timestamp));
    }

    function test_Revert_IfBuyAmountIsZero() public {
        vm.expectRevert(IAsyncSwapper.InsufficientBuyAmount.selector);
        adapter.swap(SwapParams(PRANK_ADDRESS, 1, PRANK_ADDRESS, 0, new bytes(0), new bytes(0), block.timestamp));
    }

    function test_swap() public {
        // solhint-disable max-line-length
        bytes memory data =
            hex"415565b00000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000001954af4d2d99874cf0000000000000000000000000000000000000000000000000131f1a539c7e4a3cdf00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000001954af4d2d99874cf000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000001761dce4c7a1693f1080000000000000000000000000000000000000000000000011a9e8a52fa524243000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000b576491f1e6e5e62f1d8f26062ee822b40b0e0d465b2489b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000001f2d26865f81e0ddf800000000000000000000000000000000000000000000000017531ae6cd92618af000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b39f68862c63935ade";

        address whale = 0xcba0074a77A3aD623A80492Bb1D8d932C62a8bab;
        vm.startPrank(whale);
        transferAll(IERC20(CVX_MAINNET), whale, address(adapter));
        vm.stopPrank();

        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(adapter));

        adapter.swap(
            SwapParams(
                CVX_MAINNET,
                119_621_320_376_600_000_000_000,
                WETH_MAINNET,
                356_292_255_653_182_345_276,
                data,
                new bytes(0),
                block.timestamp
            )
        );

        uint256 balanceAfter = IERC20(WETH_MAINNET).balanceOf(address(adapter));
        uint256 balanceDiff = balanceAfter - balanceBefore;

        assertTrue(balanceDiff >= 356_292_255_653_182_345_276);
    }

    function transferAll(IERC20 token, address from, address to) private {
        uint256 balance = token.balanceOf(from);
        token.transfer(to, balance);
    }
}
