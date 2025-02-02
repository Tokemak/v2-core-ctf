// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import {
    WETH9_ADDRESS,
    TOKE_MAINNET,
    WSTETH_MAINNET,
    MAV_WSTETH_WETH_BOOSTED_POS,
    MAV_WSTETH_WETH_POOL,
    MAV_GHO_USDC_BOOSTED_POS,
    MAV_GHO_USDC_POOL,
    MAV_POOL_INFORMATION,
    WETH_MAINNET,
    USDC_MAINNET,
    GHO_MAINNET
} from "test/utils/Addresses.sol";

import { MavEthOracle } from "src/oracles/providers/MavEthOracle.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

// solhint-disable func-name-mixedcase

contract MavEthOracleTest is Test {
    event PoolInformationSet(address poolInformation);

    SystemRegistry public registry;
    AccessController public accessControl;
    RootPriceOracle public rootOracle;
    MavEthOracle public mavOracle;

    function setUp() external {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 18_579_296);
        vm.selectFork(mainnetFork);
        _setUp();
    }

    function _setUp() internal {
        registry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        accessControl = new AccessController(address(registry));
        registry.setAccessController(address(accessControl));
        rootOracle = new RootPriceOracle(registry);
        registry.setRootPriceOracle(address(rootOracle));
        mavOracle = new MavEthOracle(registry, MAV_POOL_INFORMATION);

        accessControl.grantRole(Roles.ORACLE_MANAGER, address(this));
    }

    // Constructor tests
    function test_RevertSystemRegistryZeroAddress() external {
        // Reverts with generic evm revert.
        vm.expectRevert();
        new MavEthOracle(ISystemRegistry(address(0)), MAV_POOL_INFORMATION);
    }

    function test_RevertPoolInformationZeroAddress() external {
        // Reverts with generic evm revert.
        vm.expectRevert();
        new MavEthOracle(registry, address(0));
    }

    function test_RevertRootPriceOracleZeroAddress() external {
        // Doesn't have root oracle set.
        SystemRegistry localSystemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        AccessController localAccessControl = new AccessController(address(localSystemRegistry));
        localSystemRegistry.setAccessController(address(localAccessControl));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "priceOracle"));
        new MavEthOracle(ISystemRegistry(address(localSystemRegistry)), MAV_POOL_INFORMATION);
    }

    function test_ProperlySetsState() external {
        assertEq(mavOracle.getSystemRegistry(), address(registry));
    }

    // Test setPoolInformation error case
    function test_SetPoolInformation_RevertIf_ZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_poolInformation"));
        mavOracle.setPoolInformation(address(0));
    }

    // Test setPoolInformation event
    function test_SetPoolInformation_Emits_PoolInformationSetEvent() external {
        vm.expectEmit(false, false, false, true);
        emit PoolInformationSet(MAV_POOL_INFORMATION);

        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);
    }

    // Test setPoolInformation state
    function test_SetPoolInformation() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        assertEq(address(mavOracle.poolInformation()), MAV_POOL_INFORMATION);
    }

    function test_SetPoolInformation_RevertIf_UnAuthorized() external {
        vm.prank(makeAddr("fake"));
        vm.expectRevert(abi.encodeWithSelector(IAccessController.AccessDenied.selector));
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);
    }

    // Test getSpotPrice error case
    function test_GetSpotPrice_RevertIf_PoolZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "poolAddress"));
        mavOracle.getSpotPrice(WSTETH_MAINNET, address(0), WETH_MAINNET);
    }

    function test_GetSpotPrice_RevertIf_InvalidToken() external {
        vm.expectRevert(abi.encodeWithSelector(MavEthOracle.InvalidToken.selector));
        mavOracle.getSpotPrice(address(0), MAV_WSTETH_WETH_POOL, WETH_MAINNET);
    }

    /// @dev WestEth -> Weth at block 18_579_296 is 1.146037777780535053
    function test_GetSpotPrice_WstEthWeth() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (uint256 price,) = mavOracle.getSpotPrice(WSTETH_MAINNET, MAV_WSTETH_WETH_POOL, WETH_MAINNET);

        assertEq(price, 1_146_037_777_780_535_053);
    }

    /// @dev Weth -> WestEth at block 18_579_296 is 0.872571584407596759
    function test_GetSpotPrice_WethWstEth() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (uint256 price,) = mavOracle.getSpotPrice(WETH_MAINNET, MAV_WSTETH_WETH_POOL, WSTETH_MAINNET);

        assertEq(price, 872_571_584_407_596_759);
    }

    function test_GetSpotPrice_ReturnActualQuoteToken() external {
        mavOracle.setPoolInformation(MAV_POOL_INFORMATION);

        (, address actualQuoteToken) = mavOracle.getSpotPrice(WETH_MAINNET, MAV_WSTETH_WETH_POOL, address(0));

        // Asking for Weth -> address(0), so should return wsEth.
        assertEq(actualQuoteToken, WSTETH_MAINNET);
    }
}

contract GetSafeSpotPriceInfo is MavEthOracleTest {
    function test_getSafeSpotPrice_RevertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        mavOracle.getSafeSpotPriceInfo(address(0), MAV_WSTETH_WETH_BOOSTED_POS, WETH_MAINNET);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_boostedPosition"));
        mavOracle.getSafeSpotPriceInfo(MAV_WSTETH_WETH_POOL, address(0), WETH_MAINNET);
    }

    function test_getSafeSpotPriceInfo() public {
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            mavOracle.getSafeSpotPriceInfo(MAV_WSTETH_WETH_POOL, MAV_WSTETH_WETH_BOOSTED_POS, WETH_MAINNET);

        assertEq(reserves.length, 2);
        assertEq(totalLPSupply, 1_583_228_439_277_980_125_577);
        assertEq(reserves[0].token, WSTETH_MAINNET);
        assertEq(reserves[0].reserveAmount, 1_219_492_263_128_448_752_227);
        assertEq(reserves[0].rawSpotPrice, 1_146_037_777_780_535_053);
        assertEq(reserves[0].actualQuoteToken, WETH_MAINNET);
        assertEq(reserves[1].token, WETH_MAINNET);
        assertEq(reserves[1].reserveAmount, 649_912_488_471_763_583_072);
        assertEq(reserves[1].rawSpotPrice, 872_571_584_407_596_759);
        assertEq(reserves[1].actualQuoteToken, WSTETH_MAINNET);
    }

    function test_getSafeSpotPriceInfo_GHO_USDC() public {
        uint256 anotherFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_320_623);
        vm.selectFork(anotherFork);

        _setUp();

        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            mavOracle.getSafeSpotPriceInfo(MAV_GHO_USDC_POOL, MAV_GHO_USDC_BOOSTED_POS, USDC_MAINNET);

        assertEq(reserves.length, 2);

        assertEq(totalLPSupply, 227_572_117_208_808_237_777_026);
        assertEq(reserves[0].token, GHO_MAINNET);
        assertEq(reserves[0].reserveAmount, 844_656_614_858_709_786_752_942);

        assertEq(reserves[1].token, USDC_MAINNET);
        assertEq(reserves[1].reserveAmount, 1_535_259_704_184_092_811_945_619 / uint256(1e12));
    }
}
