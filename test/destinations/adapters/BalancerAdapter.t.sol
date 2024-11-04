// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable max-line-length

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { BalancerBeethovenAdapter } from "src/destinations/adapters/BalancerBeethovenAdapter.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import {
    WETH_MAINNET,
    RETH_MAINNET,
    WSTETH_MAINNET,
    SFRXETH_MAINNET,
    CBETH_MAINNET,
    WSTETH_ARBITRUM,
    WETH_ARBITRUM
} from "test/utils/Addresses.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";

contract BalancerAdapterTest is Test {
    uint256 public mainnetFork;

    IVault private vault;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_536_359);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    function forkArbitrum() private {
        string memory endpoint = vm.envString("ARBITRUM_MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(endpoint);
        vm.selectFork(forkId);
        assertEq(vm.activeFork(), forkId);

        vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    function testRevertIfNonZeroAmountProvided() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 0;
        withdrawAmounts[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.NoNonZeroAmountProvided.selector));
        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, 1);
    }

    function testRevertIfArraysLengthMismatch() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        address[] memory tokens = new address[](0);

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.ArraysLengthMismatch.selector));
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, 1);
    }

    function testRevertIfPoolTokenMismatch() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;

        address[] memory tokens = new address[](3);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;
        tokens[2] = CBETH_MAINNET;

        uint256[] memory withdrawAmounts = new uint256[](3);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        withdrawAmounts[2] = 1 * 1e18;

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.ArraysLengthMismatch.selector));
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, 1);
    }

    function testRevertIfInvalidBalanceChange() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        // Mock the call so balance before and after are equal
        vm.mockCall(poolAddress, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(1000));

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.InvalidBalanceChange.selector));
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);
    }

    function testRevertIfBalanceDidNotIncrease() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        // Mock the call so balance is 0
        vm.mockCall(WSTETH_MAINNET, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

        vm.expectRevert(abi.encodeWithSelector(BalancerBeethovenAdapter.BalanceMustIncrease.selector));
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);
    }

    function testRemoveLiquidityWstEthCbEth() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthCbEth() public {
        address poolAddress = 0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = CBETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);

        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthWeth() public {
        address poolAddress = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceRethWeth() public {
        address poolAddress = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(RETH_MAINNET), address(this), 2 * 1e18);
        deal(address(WETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH_MAINNET;
        tokens[1] = WETH_MAINNET;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 0.5 * 1e18;
        amounts[2] = 0.5 * 1e18;
        amounts[3] = 0.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        _addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[1]);
        assertEq(afterBalance2, preBalance2 - amounts[2]);
        assertEq(afterBalance3, preBalance3 - amounts[3]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 1.5 * 1e18;
        amounts[2] = 1.5 * 1e18;
        amounts[3] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        _addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory minWithdrawAmounts = new uint256[](4);
        minWithdrawAmounts[0] = 0;
        minWithdrawAmounts[1] = 1 * 1e18;
        minWithdrawAmounts[2] = 1 * 1e18;
        minWithdrawAmounts[3] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidity(vault, address(pool), tokens, minWithdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterBalance3 > preBalance3);
        assert(afterLpBalance < preLpBalance);
    }

    function testRemoveLiquidityImbalanceWstEthSfrxEthREth() public {
        // Composable pool
        IBalancerComposableStablePool pool = IBalancerComposableStablePool(0x5aEe1e99fE86960377DE9f88689616916D5DcaBe);
        IERC20 lpToken = IERC20(address(pool));

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0 * 1e18;
        amounts[1] = 1.5 * 1e18;
        amounts[2] = 1.5 * 1e18;
        amounts[3] = 1.5 * 1e18;

        deal(address(WSTETH_MAINNET), address(this), 2 * 1e18);
        deal(address(SFRXETH_MAINNET), address(this), 2 * 1e18);
        deal(address(RETH_MAINNET), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](4);
        tokens[0] = address(lpToken);
        tokens[1] = WSTETH_MAINNET;
        tokens[2] = SFRXETH_MAINNET;
        tokens[3] = RETH_MAINNET;

        _addLiquidity(vault, address(pool), tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 preBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](4);
        withdrawAmounts[0] = 0;
        withdrawAmounts[1] = 1 * 1e18;
        withdrawAmounts[2] = 1 * 1e18;
        withdrawAmounts[3] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, address(pool), tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(SFRXETH_MAINNET).balanceOf(address(this));
        uint256 afterBalance3 = IERC20(RETH_MAINNET).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterBalance3 > preBalance3);
        assert(afterLpBalance < preLpBalance);
    }

    function testAddLiquidityWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 * 1e18;
        amounts[1] = 0.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);

        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assertEq(afterBalance1, preBalance1 - amounts[0]);
        assertEq(afterBalance2, preBalance2 - amounts[1]);
        assert(afterLpBalance > preLpBalance);
    }

    function testRemoveLiquidityWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);
        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;
        BalancerBeethovenAdapter.removeLiquidity(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance == 0);
    }

    function testRemoveLiquidityImbalanceWstEthWethArbitrum() public {
        forkArbitrum();

        address poolAddress = 0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f;
        IERC20 lpToken = IERC20(poolAddress);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1.5 * 1e18;
        amounts[1] = 1.5 * 1e18;

        deal(address(WSTETH_ARBITRUM), address(this), 2 * 1e18);
        deal(address(WETH_ARBITRUM), address(this), 2 * 1e18);

        uint256 minLpMintAmount = 1;

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH_ARBITRUM;
        tokens[1] = WETH_ARBITRUM;

        _addLiquidity(vault, poolAddress, tokens, amounts, minLpMintAmount);

        uint256 preBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 preBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 preLpBalance = lpToken.balanceOf(address(this));

        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1 * 1e18;
        withdrawAmounts[1] = 1 * 1e18;

        BalancerBeethovenAdapter.removeLiquidityImbalance(vault, poolAddress, tokens, withdrawAmounts, preLpBalance);

        uint256 afterBalance1 = IERC20(WSTETH_ARBITRUM).balanceOf(address(this));
        uint256 afterBalance2 = IERC20(WETH_ARBITRUM).balanceOf(address(this));
        uint256 afterLpBalance = lpToken.balanceOf(address(this));

        assert(afterBalance1 > preBalance1);
        assert(afterBalance2 > preBalance2);
        assert(afterLpBalance < preLpBalance);
    }

    /**
     * @notice Deploy liquidity to Balancer or Beethoven pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param _vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to deploy liquidity to
     * @param tokens Addresses of tokens to deploy. Should match pool tokens
     * @param exactTokenAmounts Array of exact amounts of tokens to be deployed
     * @param minLpMintAmount Min amount of LP tokens to mint on deposit
     */
    function _addLiquidity(
        IVault _vault,
        address pool,
        address[] memory tokens,
        uint256[] memory exactTokenAmounts,
        uint256 minLpMintAmount
    ) private {
        bytes32 poolId = IBalancerPool(pool).getPoolId();

        // verify that we're passing correct pool tokens
        _approveTokens(_vault, exactTokenAmounts, tokens);

        // record BPT balances before deposit 0 - balance before; 1 - balance after
        uint256[] memory bptBalances = new uint256[](2);
        bptBalances[0] = IBalancerPool(pool).balanceOf(address(this));

        _vault.joinPool(
            poolId,
            address(this), // sender
            address(this), // recipient of BPT token
            _getJoinPoolRequest(pool, tokens, exactTokenAmounts, minLpMintAmount)
        );
    }

    /**
     * @notice Validate that given tokens are relying to the given pool and approve spend
     * @dev Separate function to avoid stack-too-deep errors
     * and combine gas-costly loop operations into single loop
     * @param amounts Amounts of corresponding tokens to approve
     */
    function _approveTokens(IVault _vault, uint256[] memory amounts, address[] memory tokens) private {
        uint256 nTokens = amounts.length;

        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 currentAmount = amounts[i];
            IERC20 currentToken = IERC20(tokens[i]);

            // grant spending approval to balancer's Vault
            if (currentAmount != 0) {
                LibAdapter._approve(currentToken, address(_vault), currentAmount);
            }
        }
    }

    /**
     * @notice Generate request for Balancer's Vault to join the pool
     * @dev Separate function to avoid stack-too-deep errors
     * @param tokens Tokens to be deposited into pool
     * @param amounts Amounts of corresponding tokens to deposit
     * @param poolAmountOut Expected amount of LP tokens to be minted on deposit
     */
    function _getJoinPoolRequest(
        address pool,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 poolAmountOut
    ) private view returns (IVault.JoinPoolRequest memory joinRequest) {
        uint256[] memory amountsUser = _getUserAmounts(pool, amounts);

        joinRequest = IVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amounts, // maxAmountsIn,
            userData: abi.encode(
                IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsUser, //maxAmountsIn,
                poolAmountOut
            ),
            fromInternalBalance: false
        });
    }

    /**
     * @notice We should exclude BPT amount from amounts array for userData in ComposablePools
     * @param pool Balancer or Beethoven pool address
     * @param amountsOut array of pool token amounts that length-equal with IVault#getPoolTokens array
     */
    function _getUserAmounts(
        address pool,
        uint256[] memory amountsOut
    ) private view returns (uint256[] memory amountsUser) {
        if (BalancerUtilities.isComposablePool(pool)) {
            uint256 uix = 0;
            uint256 bptIndex = IBalancerComposableStablePool(pool).getBptIndex();
            uint256 nTokens = amountsOut.length;
            amountsUser = new uint256[](nTokens - 1);
            for (uint256 i = 0; i < nTokens; i++) {
                if (i != bptIndex) {
                    amountsUser[uix] = amountsOut[i];
                    uix++;
                }
            }
        } else {
            amountsUser = amountsOut;
        }
    }
}
