// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
// solhint-disable func-name-mixedcase,var-name-mixedcase
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { RootPriceOracle } from "src/oracles/RootPriceOracle.sol";
import { AccessController } from "src/security/AccessController.sol";
import { StatsCalculatorFactory } from "src/stats/StatsCalculatorFactory.sol";
import { StatsCalculatorRegistry } from "src/stats/StatsCalculatorRegistry.sol";
import { BalancerStablePoolCalculatorBase } from "src/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerComposableStablePoolCalculator } from
    "src/stats/calculators/BalancerComposableStablePoolCalculator.sol";
import {
    BAL_VAULT,
    TOKE_MAINNET,
    WETH_MAINNET,
    WSTETH_MAINNET,
    SFRXETH_MAINNET,
    RETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL
} from "test/utils/Addresses.sol";

contract BalancerComposableStablePoolCalculatorTest is Test {
    TestBalancerCalculator private calculator;

    function testGetPoolTokens() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_735_327);

        prepare();

        (IERC20[] memory assets, uint256[] memory balances) = calculator.verifyGetPoolTokens();

        // Verify assets
        assertEq(assets.length, 3);
        assertEq(address(assets[0]), WSTETH_MAINNET);
        assertEq(address(assets[1]), SFRXETH_MAINNET);
        assertEq(address(assets[2]), RETH_MAINNET);
        // Verify balances
        assertEq(balances.length, 3);
        assertEq(balances[0], 380_949_500_227_632_620_189);
        assertEq(balances[1], 634_919_600_886_552_074_720);
        assertEq(balances[2], 166_972_211_148_502_452_054);
    }

    function testGetVirtualPrice() public {
        checkVirtualPrice(17_272_708, 1_008_603_952_713_993_910);
        checkVirtualPrice(17_279_454, 1_008_691_853_542_824_890);
        checkVirtualPrice(17_286_461, 1_008_780_765_081_415_495);
        checkVirtualPrice(17_293_521, 1_008_881_220_902_358_371);
        checkVirtualPrice(17_393_019, 1_009_838_934_074_695_557);
    }

    function checkVirtualPrice(uint256 targetBlock, uint256 expected) private {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), targetBlock);

        prepare();

        assertEq(calculator.verifyGetVirtualPrice(), expected);
    }

    function prepare() private {
        // System setup
        SystemRegistry systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));

        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));
        accessController.grantRole(Roles.STATS_CALC_REGISTRY_MANAGER, address(this));

        StatsCalculatorRegistry statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        StatsCalculatorFactory statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));

        // Calculator setup
        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        bytes32[] memory depAprIds = new bytes32[](3);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;
        depAprIds[2] = Stats.NOOP_APR_ID;

        calculator.initialize(
            depAprIds,
            abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: WSETH_RETH_SFRXETH_BAL_POOL }))
        );
    }
}

contract TestComposableStablePoolIsExemptFromYieldProtocolFee is Test {
    TestBalancerCalculator private calculator;
    SystemRegistry private systemRegistry;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_565_365);

        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController accessController = new AccessController(address(systemRegistry));

        systemRegistry.setAccessController(address(accessController));
        accessController.grantRole(Roles.STATS_SNAPSHOT_EXECUTOR, address(this));
        accessController.grantRole(Roles.STATS_CALC_REGISTRY_MANAGER, address(this));

        StatsCalculatorRegistry statsRegistry = new StatsCalculatorRegistry(systemRegistry);
        systemRegistry.setStatsCalculatorRegistry(address(statsRegistry));

        StatsCalculatorFactory statsFactory = new StatsCalculatorFactory(systemRegistry);
        statsRegistry.setCalculatorFactory(address(statsFactory));

        RootPriceOracle rootPriceOracle = new RootPriceOracle(systemRegistry);
        systemRegistry.setRootPriceOracle(address(rootPriceOracle));
    }

    function test_isExemptFromYieldProtocolFee_FalseRecent() public {
        /// @dev ComposableStablePools changed their interface slightly this makes sure it works with old and new pools
        address swETH_WETH_bal_pool = 0x5aEe1e99fE86960377DE9f88689616916D5DcaBe;
        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        bytes32[] memory depAprIds = new bytes32[](3);
        depAprIds[0] = Stats.NOOP_APR_ID; // the pool token
        depAprIds[1] = Stats.NOOP_APR_ID;
        depAprIds[2] = Stats.NOOP_APR_ID;

        calculator.initialize(
            depAprIds, abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: swETH_WETH_bal_pool }))
        );
        assertFalse(calculator.isExemptFromYieldProtocolFee());
    }

    function test_isExemptFromYieldProtocolFee_FalseOld() public {
        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        bytes32[] memory depAprIds = new bytes32[](3);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;
        depAprIds[2] = Stats.NOOP_APR_ID;

        calculator.initialize(
            depAprIds,
            abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: WSETH_RETH_SFRXETH_BAL_POOL }))
        );
        assertFalse(calculator.isExemptFromYieldProtocolFee());
    }

    function test_isExemptFromYieldProtocolFee_TrueNew() public {
        calculator =
            TestBalancerCalculator(Clones.clone(address(new TestBalancerCalculator(systemRegistry, BAL_VAULT))));

        address osETH_WETH_bal_pool = 0xDACf5Fa19b1f720111609043ac67A9818262850c;
        bytes32[] memory depAprIds = new bytes32[](2);
        depAprIds[0] = Stats.NOOP_APR_ID;
        depAprIds[1] = Stats.NOOP_APR_ID;

        calculator.initialize(
            depAprIds, abi.encode(BalancerStablePoolCalculatorBase.InitData({ poolAddress: osETH_WETH_bal_pool }))
        );
        assertTrue(calculator.isExemptFromYieldProtocolFee());
    }
}

contract TestBalancerCalculator is BalancerComposableStablePoolCalculator {
    constructor(
        ISystemRegistry _systemRegistry,
        address vault
    ) BalancerComposableStablePoolCalculator(_systemRegistry, vault) { }

    function verifyGetVirtualPrice() public view returns (uint256) {
        return getVirtualPrice();
    }

    function verifyGetPoolTokens() public view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return getPoolTokens();
    }
}
