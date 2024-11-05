// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { WETH9_BASE, WSTETH_BASE } from "test/utils/Addresses.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { BankSwapper } from "src/liquidation/BankSwapper.sol";
import { SystemRegistryL2 } from "src/SystemRegistryL2.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SwapParams, IAsyncSwapper } from "src/interfaces/liquidation/IAsyncSwapper.sol";

// solhint-disable func-name-mixedcase

contract BankSwapperTest is Test {
    event Swapped(
        address indexed sellTokenAddress,
        address indexed buyTokenAddress,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 buyTokenAmountReceived
    );

    BankSwapper public swapper;

    address public toke;
    address public bank;
    SystemRegistryL2 public registry;
    AccessController public access;
    SwapParams public swapParams;

    function setUp() public {
        // Can technically be used anywhere, but as of right now plan is for Base so using Base fork
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 21_115_651);

        // SystemReg
        toke = makeAddr("Toke");
        registry = new SystemRegistryL2(toke, WETH9_BASE);

        // Access
        access = new AccessController(address(registry));
        registry.setAccessController(address(access));

        // Swapper
        bank = makeAddr("Bank");
        swapper = new BankSwapper(bank, registry);

        // Set up default swap params
        swapParams = SwapParams({
            sellTokenAddress: WSTETH_BASE,
            sellAmount: 1e18,
            buyTokenAddress: WETH9_BASE,
            buyAmount: 1.1e18,
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });
    }

    function _setupRole() private {
        access.setupRole(Roles.BANK_SWAP_MANAGER, address(this));
    }

    function test_RevertIf_DelegatcallIncorrectRole() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
    }

    // Testing access control via normal call
    function test_Revert_WhenCalled() public {
        // Set up role correctly (liquidator would have role) and try using regular call
        _setupRole();

        vm.expectRevert(Errors.AccessDenied.selector);
        Address.functionCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
    }

    function test_RevertIf_ZeroValuesSwapParams() public {
        _setupRole();

        swapParams.sellTokenAddress = address(0);
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        swapParams.sellTokenAddress = WSTETH_BASE;

        swapParams.buyTokenAddress = address(0);
        vm.expectRevert(IAsyncSwapper.TokenAddressZero.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        swapParams.buyTokenAddress = WETH9_BASE;

        swapParams.sellAmount = 0;
        vm.expectRevert(IAsyncSwapper.InsufficientSellAmount.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        swapParams.sellAmount = 1e18;

        swapParams.buyAmount = 0;
        vm.expectRevert(IAsyncSwapper.InsufficientBuyAmount.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        swapParams.buyAmount = 1.1e18;
    }

    function test_RevertIf_NotEnoughSellToken() public {
        _setupRole();
        assertEq(IERC20(WSTETH_BASE).balanceOf(address(this)), 0);

        vm.expectRevert(abi.encodeWithSelector(IAsyncSwapper.InsufficientBalance.selector, 0, 1e18));
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
    }

    function test_RevertIf_BalanceOfBuyToken_InBank_NotEnoughForSwap() public {
        _setupRole();
        deal(WSTETH_BASE, address(this), 1e18);
        assertEq(IERC20(WETH9_BASE).balanceOf(bank), 0);

        vm.expectRevert(IAsyncSwapper.SwapFailed.selector);
        Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
    }

    function test_RunsProperly_EmitsEvent_CorrectBalances() public {
        _setupRole();

        // Give each swap participant the amount of funds needed
        deal(WSTETH_BASE, address(this), 1e18);
        deal(WETH9_BASE, bank, 1.1e18);

        // Bank approval
        vm.startPrank(bank);
        IERC20(WETH9_BASE).approve(address(this), 1.1e18);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Swapped(
            swapParams.sellTokenAddress,
            swapParams.buyTokenAddress,
            swapParams.sellAmount,
            swapParams.buyAmount,
            swapParams.buyAmount
        );
        bytes memory data =
            Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        uint256 amountReceived = abi.decode(data, (uint256));

        assertEq(amountReceived, 1.1e18);
        assertEq(IERC20(WSTETH_BASE).balanceOf(address(this)), 0);
        assertEq(IERC20(WSTETH_BASE).balanceOf(bank), 1e18);
        assertEq(IERC20(WETH9_BASE).balanceOf(address(this)), 1.1e18);
        assertEq(IERC20(WETH9_BASE).balanceOf(bank), 0);
    }
}
