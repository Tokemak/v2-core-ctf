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
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
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
    IRootPriceOracle public oracle;
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

        // Oracle
        oracle = IRootPriceOracle(makeAddr("Oracle"));
        vm.mockCall(address(oracle), abi.encodeWithSignature("getSystemRegistry()"), abi.encode(address(registry)));
        registry.setRootPriceOracle(address(oracle));

        // Swapper
        bank = makeAddr("Bank");
        swapper = new BankSwapper(bank, registry);

        // Set up default swap params
        swapParams = SwapParams({
            sellTokenAddress: WSTETH_BASE,
            sellAmount: 1e18,
            buyTokenAddress: WETH9_BASE,
            buyAmount: 0, // Doesn't matter in this context, determined by oracle pricing
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });
    }

    function _setupRole() private {
        access.setupRole(Roles.BANK_SWAP_MANAGER, address(this));
    }

    function _mockOracle(address token, uint256 price) private {
        vm.mockCall(address(oracle), abi.encodeCall(IRootPriceOracle.getPriceInEth, (token)), abi.encode(price));
    }

    function test_Revert_Construction() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_bank"));
        new BankSwapper(address(0), registry);

        vm.mockCall(address(registry), abi.encodeWithSignature("rootPriceOracle()"), abi.encode(address(0)));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_systemRegistry.rootPriceOracle"));
        new BankSwapper(bank, registry);
    }

    function test_RevertIf_DelegatecallIncorrectRole() public {
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

    function test_IgnoresBuyAmount_RunsProperly() public {
        uint256 wethPrice = 1e18;
        uint256 wstEthPrice = 1.1e18;

        _setupRole();

        // Give each swap participant the amount of funds needed
        deal(WSTETH_BASE, address(this), 1e18);
        deal(WETH9_BASE, bank, 1.1e18);

        // Bank approval
        vm.startPrank(bank);
        IERC20(WETH9_BASE).approve(address(this), type(uint256).max);
        vm.stopPrank();

        // Updating swap params - Ridiculous number received for amount sent
        swapParams.buyAmount = 1e25;

        // Oracle mocks
        _mockOracle(WETH9_BASE, wethPrice);
        _mockOracle(WSTETH_BASE, wstEthPrice);

        // Calculate amount received via swap
        uint256 expectedReceived = swapParams.sellAmount * wstEthPrice / wethPrice;

        // Swap and checks
        vm.expectEmit(true, true, true, true);
        emit Swapped(
            swapParams.sellTokenAddress,
            swapParams.buyTokenAddress,
            swapParams.sellAmount,
            expectedReceived,
            expectedReceived
        );
        bytes memory data =
            Address.functionDelegateCall(address(swapper), abi.encodeCall(IAsyncSwapper.swap, (swapParams)));
        uint256 amountReceived = abi.decode(data, (uint256));

        assertEq(amountReceived, expectedReceived);
        assertEq(IERC20(WSTETH_BASE).balanceOf(address(this)), 0);
        assertEq(IERC20(WSTETH_BASE).balanceOf(bank), 1e18);
        assertEq(IERC20(WETH9_BASE).balanceOf(address(this)), expectedReceived);
        assertEq(IERC20(WETH9_BASE).balanceOf(bank), 0);
    }
}
