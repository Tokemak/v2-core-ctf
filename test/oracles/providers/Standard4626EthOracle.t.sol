// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC4626 } from "src/interfaces/vault/IERC4626.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { RedstoneOracle } from "src/oracles/providers/RedstoneOracle.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { BaseOracleDenominations } from "src/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { IAggregatorV3Interface } from "src/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { ISfrxEth } from "src/interfaces/external/frax/ISfrxEth.sol";
import { Standard4626EthOracle } from "src/oracles/providers/Standard4626EthOracle.sol";
import {
    TOKE_MAINNET,
    WETH9_ADDRESS,
    FRXETH_MAINNET,
    SFRXETH_MAINNET,
    SFRXETH_RS_FEED_MAINNET
} from "test/utils/Addresses.sol";

/*
 * Tests Standard46426EthOracle with frxETH and sfrxETH 
 *
 */

contract Standard46426EthOracleTests is Test {
    RootPriceOracle public rootPriceOracle;
    SystemRegistry public systemRegistry;
    Standard4626EthOracle public oracle;
    ISfrxEth public sfrxETH;
    RedstoneOracle public sfrxETHRedstoneOracle;

    SystemRegistry public systemRegistry2;
    Standard4626EthOracle public oracle2;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_711_565);
        vm.selectFork(mainnetFork);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);
        AccessController accessControl = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessControl));
        rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        oracle = new Standard4626EthOracle(systemRegistry, SFRXETH_MAINNET);
        sfrxETH = ISfrxEth(SFRXETH_MAINNET);
        sfrxETHRedstoneOracle = new RedstoneOracle(systemRegistry);

        accessControl.grantRole(Roles.ORACLE_MANAGER, address(this));
        sfrxETHRedstoneOracle.registerOracle(
            SFRXETH_MAINNET,
            IAggregatorV3Interface(SFRXETH_RS_FEED_MAINNET),
            BaseOracleDenominations.Denomination.ETH,
            24 hours
        );

        rootPriceOracle.registerMapping(SFRXETH_MAINNET, sfrxETHRedstoneOracle);
    }
}

contract Construct is Standard46426EthOracleTests {
    //Constructor Tests
    function test_OracleInitializedState() public {
        uint256 vaultTokenOne = 10 ** IERC4626(SFRXETH_MAINNET).decimals();

        assertEq(address(oracle.vault()), SFRXETH_MAINNET);
        assertEq(address(oracle.underlyingAsset()), FRXETH_MAINNET);
        assertEq(vaultTokenOne, oracle.vaultTokenOne());
    }

    function test_RevertSystemRegistryZeroAddress() public {
        vm.expectRevert();
        oracle = new Standard4626EthOracle(ISystemRegistry(address(0)), SFRXETH_MAINNET);
    }

    function test_RevertVaultZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_vault4626"));
        oracle = new Standard4626EthOracle(systemRegistry, address(0));
    }

    function test_RevertRootPriceOracleNotSetup() public {
        systemRegistry2 = new SystemRegistry(TOKE_MAINNET, WETH9_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "rootPriceOracle"));
        oracle2 = new Standard4626EthOracle(systemRegistry2, SFRXETH_MAINNET);
    }
}

contract GetDescription is Standard46426EthOracleTests {
    function test_description() public {
        string memory description = oracle.getDescription();
        assertEq(description, "frxETH");
    }
}

contract GetPriceInEth is Standard46426EthOracleTests {
    function testBasicPriceFRXETH() public {
        uint256 expectedPrice = 996_304_328_573_279_558;
        uint256 price = oracle.getPriceInEth(FRXETH_MAINNET);
        assertApproxEqAbs(price, expectedPrice, 1e17);
    }

    function testInvalidToken() public {
        address fakeAddr = vm.addr(34_343);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToken.selector, fakeAddr));
        oracle.getPriceInEth(address(fakeAddr));
    }
}
