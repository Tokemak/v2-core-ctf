// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/* solhint-disable func-name-mixedcase */

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { BaseSetCalculator } from "src/stats/calculators/set/BaseSetCalculator.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { StatsTransientCacheStore } from "src/stats/calculators/set/StatsTransientCacheStore.sol";
import { DexIncentiveSetCalculator } from "src/stats/calculators/set/DexIncentiveSetCalculator.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";

abstract contract DexIncentiveSetCalculatorTests is Test {
    SystemRegistry internal systemRegistry;
    AccessController internal accessController;
    address internal owner = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;

    StatsTransientCacheStore internal cacheStore;
    DexIncentiveSetCalculator internal calculatorTemplate;
    DexIncentiveSetCalculator internal calculator;

    BaseSetCalculator.InitData internal initData;

    function setUp() external {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 21_336_808);
        vm.selectFork(forkId);

        systemRegistry = SystemRegistry(0x2218F90A98b0C070676f249EF44834686dAa4285);
        accessController = AccessController(address(systemRegistry.accessController()));

        cacheStore = new StatsTransientCacheStore(systemRegistry);
        calculatorTemplate = new DexIncentiveSetCalculator(systemRegistry);

        calculator = DexIncentiveSetCalculator(Clones.clone(address(calculatorTemplate)));

        address[] memory baseCalculators = new address[](1);
        baseCalculators[0] = makeAddr("baseCalculator");
        initData = BaseSetCalculator.InitData({
            addressId: makeAddr("addressId"),
            baseCalculators: baseCalculators,
            cacheStore: address(cacheStore),
            aprId: keccak256("aprId"),
            calcType: "base"
        });
        calculator.initialize(new bytes32[](0), abi.encode(initData));
    }
}

contract Current is DexIncentiveSetCalculatorTests {
    function test_ReturnsEmptyFromCacheWhenDifferentAprIdSet() external {
        vm.prank(owner);
        accessController.grantRole(Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR, address(this));

        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = keccak256("badAprId");

        bytes[] memory calcData = new bytes[](1);
        IDexLSTStats.DexLSTStatsData memory mockData = getMockDexLstStatData();
        calcData[0] = abi.encode(mockData);
        cacheStore.writeTransient(aprIds, calcData);

        IDexLSTStats.DexLSTStatsData memory queryData = calculator.current();

        assertDexStatsEmpty(queryData);
    }

    function test_ReturnsDataFromTransientCache() external {
        vm.prank(owner);
        accessController.grantRole(Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR, address(this));

        bytes32[] memory aprIds = new bytes32[](1);
        aprIds[0] = initData.aprId;

        bytes[] memory calcData = new bytes[](1);
        IDexLSTStats.DexLSTStatsData memory mockData = getMockDexLstStatData();
        calcData[0] = abi.encode(mockData);
        cacheStore.writeTransient(aprIds, calcData);

        IDexLSTStats.DexLSTStatsData memory queryData = calculator.current();

        assertDexStatsEqual(mockData, queryData);
    }

    function test_ReturnsEmptyDataIfNoneInTransient() external {
        assertEq(false, cacheStore.hasTransient(initData.aprId), "false");

        IDexLSTStats.DexLSTStatsData memory data = calculator.current();

        assertDexStatsEmpty(data);
    }

    function assertDexStatsEqual(
        IDexLSTStats.DexLSTStatsData memory data,
        IDexLSTStats.DexLSTStatsData memory data2
    ) internal {
        assertEq(data.lastSnapshotTimestamp, data2.lastSnapshotTimestamp, "timestamp");
        assertEq(data.feeApr, data2.feeApr, "feeApr");
        assertEq(data.reservesInEth.length, data2.reservesInEth.length, "reservesInEth");
        for (uint256 i = 0; i < data.reservesInEth.length; i++) {
            assertEq(
                data.reservesInEth[i],
                data2.reservesInEth[i],
                string.concat("reservesInEth", string(abi.encodePacked(i)))
            );
        }
        assertEq(
            data.stakingIncentiveStats.safeTotalSupply,
            data2.stakingIncentiveStats.safeTotalSupply,
            "stakingIncentiveStats.safeTotalSupply"
        );
        assertEq(
            data.stakingIncentiveStats.rewardTokens.length,
            data2.stakingIncentiveStats.rewardTokens.length,
            "stakingIncentiveStats.rewardTokens"
        );
        for (uint256 i = 0; i < data.stakingIncentiveStats.rewardTokens.length; i++) {
            assertEq(
                data.stakingIncentiveStats.rewardTokens[i],
                data2.stakingIncentiveStats.rewardTokens[i],
                string.concat("stakingIncentiveStats.rewardTokens", string(abi.encodePacked(i)))
            );
        }
        assertEq(
            data.stakingIncentiveStats.annualizedRewardAmounts.length,
            data2.stakingIncentiveStats.annualizedRewardAmounts.length,
            "stakingIncentiveStats.annualizedRewardAmounts"
        );
        for (uint256 i = 0; i < data.stakingIncentiveStats.annualizedRewardAmounts.length; i++) {
            assertEq(
                data.stakingIncentiveStats.annualizedRewardAmounts[i],
                data2.stakingIncentiveStats.annualizedRewardAmounts[i],
                string.concat("stakingIncentiveStats.annualizedRewardAmounts", string(abi.encodePacked(i)))
            );
        }
        assertEq(
            data.stakingIncentiveStats.periodFinishForRewards.length,
            data2.stakingIncentiveStats.periodFinishForRewards.length,
            "stakingIncentiveStats.periodFinishForRewards"
        );
        for (uint256 i = 0; i < data.stakingIncentiveStats.periodFinishForRewards.length; i++) {
            assertEq(
                data.stakingIncentiveStats.periodFinishForRewards[i],
                data2.stakingIncentiveStats.periodFinishForRewards[i],
                string.concat("stakingIncentiveStats.periodFinishForRewards", string(abi.encodePacked(i)))
            );
        }
        assertEq(
            data.stakingIncentiveStats.incentiveCredits,
            data2.stakingIncentiveStats.incentiveCredits,
            "stakingIncentiveStats.incentiveCredits"
        );
        assertEq(data.lstStatsData.length, data2.lstStatsData.length, "lstStatsData");
    }

    function assertDexStatsEmpty(
        IDexLSTStats.DexLSTStatsData memory data
    ) internal {
        assertEq(data.lastSnapshotTimestamp, 0, "timestamp");
        assertEq(data.feeApr, 0, "feeApr");
        assertEq(data.reservesInEth.length, 0, "reservesInEth");
        assertEq(data.stakingIncentiveStats.safeTotalSupply, 0, "stakingIncentiveStats.safeTotalSupply");
        assertEq(data.stakingIncentiveStats.rewardTokens.length, 0, "stakingIncentiveStats.rewardTokens");
        assertEq(
            data.stakingIncentiveStats.annualizedRewardAmounts.length,
            0,
            "stakingIncentiveStats.annualizedRewardAmounts"
        );
        assertEq(
            data.stakingIncentiveStats.periodFinishForRewards.length, 0, "stakingIncentiveStats.periodFinishForRewards"
        );
        assertEq(data.stakingIncentiveStats.incentiveCredits, 0, "stakingIncentiveStats.incentiveCredits");
        assertEq(data.lstStatsData.length, 0, "lstStatsData");
    }

    function getMockDexLstStatData() internal returns (IDexLSTStats.DexLSTStatsData memory data) {
        data.lastSnapshotTimestamp = 127_368_367;
        data.feeApr = 1.04e18;

        // IDexLSTStats.StakingIncentiveStats

        uint256[] memory reservesInEth = new uint256[](2);
        reservesInEth[0] = 100e18;
        reservesInEth[1] = 101e18;
        data.reservesInEth = reservesInEth;

        address[] memory rewardTokens = new address[](3);
        rewardTokens[0] = makeAddr("rewardToken0");
        rewardTokens[1] = makeAddr("rewardToken1");
        rewardTokens[2] = makeAddr("rewardToken2");

        uint256[] memory annualizedRewardAmounts = new uint256[](3);
        annualizedRewardAmounts[0] = 1.02e18;
        annualizedRewardAmounts[1] = 1.03e18;
        annualizedRewardAmounts[2] = 1.04e18;

        uint40[] memory periodFinishForRewards = new uint40[](3);
        periodFinishForRewards[0] = uint40(data.lastSnapshotTimestamp + 5 days);
        periodFinishForRewards[1] = uint40(data.lastSnapshotTimestamp + 6 days);
        periodFinishForRewards[2] = uint40(data.lastSnapshotTimestamp + 7 days);

        IDexLSTStats.StakingIncentiveStats memory stakingIncentiveStats = IDexLSTStats.StakingIncentiveStats({
            safeTotalSupply: 1000e18,
            rewardTokens: rewardTokens,
            annualizedRewardAmounts: annualizedRewardAmounts,
            periodFinishForRewards: periodFinishForRewards,
            incentiveCredits: 100
        });
        data.stakingIncentiveStats = stakingIncentiveStats;

        // ILSTStats.LSTStatsData[]

        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](2);
        lstStatsData[0] = ILSTStats.LSTStatsData({
            lastSnapshotTimestamp: data.lastSnapshotTimestamp,
            baseApr: 1.07e18,
            discount: -1.02e17,
            discountHistory: [
                uint24(1),
                uint24(2),
                uint24(3),
                uint24(4),
                uint24(5),
                uint24(6),
                uint24(7),
                uint24(8),
                uint24(9),
                uint24(10)
            ],
            discountTimestampByPercent: uint40(data.lastSnapshotTimestamp - 1 weeks)
        });
        lstStatsData[1] = ILSTStats.LSTStatsData({
            lastSnapshotTimestamp: data.lastSnapshotTimestamp + 1,
            baseApr: 1.07e18 + 1,
            discount: -1.02e17 + 1,
            discountHistory: [
                uint24(11),
                uint24(12),
                uint24(13),
                uint24(14),
                uint24(15),
                uint24(16),
                uint24(17),
                uint24(18),
                uint24(19),
                uint24(20)
            ],
            discountTimestampByPercent: uint40(data.lastSnapshotTimestamp - 1 weeks) + 1
        });

        data.lstStatsData = lstStatsData;
    }
}
