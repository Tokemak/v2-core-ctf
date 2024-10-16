// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-states-count */

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAccessControl } from "openzeppelin-contracts/access/IAccessControl.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { ConvexCalculator } from "src/stats/calculators/ConvexCalculator.sol";
import { ITokenWrapper } from "src/interfaces/external/convex/ITokenWrapper.sol";
import { IIncentivesPricingStats } from "src/interfaces/stats/IIncentivesPricingStats.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/interfaces/stats/ILSTStats.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";
import { LDO_MAINNET, CNC_MAINNET } from "test/utils/Addresses.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";
import { Stats } from "src/stats/Stats.sol";

contract ConvexCalculatorTest is Test {
    address internal underlyerStats;
    address internal pricingStats;
    address internal systemRegistry;
    address internal accessController;
    address internal rootPriceOracle;

    address internal mainRewarder;
    address internal mainRewarderRewardToken;
    address internal extraRewarder1;
    address internal extraRewarder2;
    address internal extraRewarder3;
    address internal platformRewarder;
    address internal extraRewarderRewardToken;
    address internal booster;
    address internal lpToken;
    address internal pool;
    address internal weth;

    ConvexCalculator internal calculator;

    uint256 internal constant REWARD_PER_TOKEN = 1000;
    uint256 internal constant REWARD_RATE = 10_000;
    uint256 internal constant REWARD_TOKEN = 8 hours;
    uint256 internal constant PERIOD_FINISH_IN = 100 days;
    uint256 internal constant DURATION = 1 weeks;
    uint256 internal constant TOTAL_SUPPLY = 100_000_000;
    uint256 internal constant EXTRA_REWARD_LENGTH = 0;
    uint40 internal constant PRICE_STALE_CHECK = 12 hours;

    error InvalidScenario();

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 18_735_327);

        underlyerStats = vm.addr(1);
        pricingStats = vm.addr(2);
        systemRegistry = vm.addr(3);
        accessController = vm.addr(1000);
        rootPriceOracle = vm.addr(4);

        mainRewarder = vm.addr(100);
        mainRewarderRewardToken = vm.addr(10_000);
        extraRewarder1 = vm.addr(101);
        extraRewarder2 = vm.addr(102);
        extraRewarder3 = vm.addr(103);
        platformRewarder = vm.addr(104);
        extraRewarderRewardToken = vm.addr(105);
        booster = vm.addr(106);
        lpToken = vm.addr(107);
        pool = vm.addr(108);
        weth = vm.addr(109);

        vm.label(underlyerStats, "underlyerStats");
        vm.label(pricingStats, "pricingStats");
        vm.label(systemRegistry, "systemRegistry");
        vm.label(rootPriceOracle, "rootPriceOracle");
        vm.label(mainRewarder, "mainRewarder");
        vm.label(extraRewarder1, "extraRewarder1");
        vm.label(extraRewarder2, "extraRewarder2");
        vm.label(extraRewarder3, "extraRewarder3");
        vm.label(platformRewarder, "platformRewarder");
        vm.label(extraRewarderRewardToken, "extraRewarderRewardToken");
        vm.label(booster, "booster");
        vm.label(lpToken, "lpToken");
        vm.label(pool, "pool");
        vm.label(weth, "weth");

        // mock system registry
        vm.mockCall(
            systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.rootPriceOracle.selector),
            abi.encode(rootPriceOracle)
        );

        vm.mockCall(
            systemRegistry,
            abi.encodeWithSelector(ISystemRegistry.accessController.selector),
            abi.encode(accessController)
        );
        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.incentivePricing.selector), abi.encode(pricingStats)
        );
        vm.mockCall(systemRegistry, abi.encodeWithSelector(ISystemRegistry.weth.selector), abi.encode(weth));

        vm.mockCall(
            accessController,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, Roles.STATS_SNAPSHOT_EXECUTOR, address(this)),
            abi.encode(true)
        );

        // mock all prices to be 1
        vm.mockCall(rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector), abi.encode(1));
        vm.mockCall(pricingStats, abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector), abi.encode(1, 1));
        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, true)
        );
        // set platform reward token (CVX) total supply
        vm.mockCall(platformRewarder, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(TOTAL_SUPPLY));

        IDexLSTStats.DexLSTStatsData memory data = IDexLSTStats.DexLSTStatsData({
            lastSnapshotTimestamp: 0,
            feeApr: 0,
            reservesInEth: new uint256[](0),
            stakingIncentiveStats: IDexLSTStats.StakingIncentiveStats({
                safeTotalSupply: 0,
                rewardTokens: new address[](0),
                annualizedRewardAmounts: new uint256[](0),
                periodFinishForRewards: new uint40[](0),
                incentiveCredits: 0
            }),
            lstStatsData: new ILSTStats.LSTStatsData[](0)
        });

        vm.mockCall(underlyerStats, abi.encodeWithSelector(IDexLSTStats.current.selector), abi.encode(data));

        mockAsset(mainRewarder, lpToken, 363);

        calculator =
            ConvexCalculator(Clones.clone(address(new ConvexCalculator(ISystemRegistry(systemRegistry), booster))));

        bytes32[] memory dependantAprs = new bytes32[](0);
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: mainRewarder,
            underlyerStats: underlyerStats,
            platformToken: platformRewarder,
            lpToken: lpToken,
            pool: pool
        });
        bytes memory encodedInitData = abi.encode(initData);

        vm.mockCall(lpToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(mainRewarderRewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(platformRewarder, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(extraRewarderRewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        calculator.initialize(dependantAprs, encodedInitData);
    }

    function mockRewardRate(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardRate.selector), abi.encode(value));
    }

    function mockPeriodFinish(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.periodFinish.selector), abi.encode(value));
    }

    function mockDuration(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.duration.selector), abi.encode(value));
    }

    function mockRewardToken(address _rewarder, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardToken.selector), abi.encode(value));
    }

    function mockExtraRewardsLength(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(value));
    }

    function mockExtraRewards(address _rewarder, uint256 index, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, index), abi.encode(value));
    }

    function mockRewardPerToken(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.rewardPerToken.selector), abi.encode(value));
    }

    function mockTotalSupply(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.totalSupply.selector), abi.encode(value));
    }

    function mockAsset(address _rewarder, address value, uint256 pid) public {
        mockPid(_rewarder, pid);

        vm.mockCall(
            booster,
            abi.encodeWithSelector(IConvexBooster.poolInfo.selector, pid),
            abi.encode(value, address(0), address(0), address(0), address(0), false)
        );
    }

    function mockPid(address _rewarder, uint256 value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(IBaseRewardPool.pid.selector), abi.encode(value));
    }

    function mockIsInvalid(address _rewarder, bool value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(ITokenWrapper.isInvalid.selector), abi.encode(value));
    }

    function mockToken(address _rewarder, address value) public {
        vm.mockCall(_rewarder, abi.encodeWithSelector(ITokenWrapper.token.selector), abi.encode(value));
    }

    function mockSimpleMainRewarder() public {
        mockSimpleMainRewarder(645);
    }

    function mockSimpleMainRewarder(
        uint256 pid
    ) public {
        mockRewardPerToken(mainRewarder, REWARD_PER_TOKEN);
        mockRewardRate(mainRewarder, REWARD_RATE);
        mockPeriodFinish(mainRewarder, block.timestamp + PERIOD_FINISH_IN);
        mockTotalSupply(mainRewarder, TOTAL_SUPPLY);
        mockRewardToken(mainRewarder, mainRewarderRewardToken);
        mockDuration(mainRewarder, DURATION);
        mockExtraRewardsLength(mainRewarder, EXTRA_REWARD_LENGTH);
        mockAsset(mainRewarder, vm.addr(1001), pid);
    }

    // mockMainRewarderWithExtraRewarder function
    function addMockExtraRewarder() public {
        mockExtraRewardsLength(mainRewarder, 1);
        mockExtraRewards(mainRewarder, 0, extraRewarder1);

        mockRewardPerToken(extraRewarder1, REWARD_PER_TOKEN);
        mockRewardRate(extraRewarder1, REWARD_RATE);
        mockPeriodFinish(extraRewarder1, block.timestamp + PERIOD_FINISH_IN);
        mockTotalSupply(extraRewarder1, TOTAL_SUPPLY);
        mockRewardToken(extraRewarder1, extraRewarderRewardToken);
        mockDuration(extraRewarder1, DURATION);
        mockExtraRewardsLength(extraRewarder1, 0);
    }

    function create2StepsSnapshot() internal {
        mockSimpleMainRewarder();
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();
    }

    function _runScenario(
        uint256[] memory rewardRates,
        uint256[] memory totalSupply,
        uint256[] memory rewardPerToken,
        uint256[] memory time
    ) internal {
        if (
            rewardRates.length != totalSupply.length || rewardRates.length != rewardPerToken.length
                || rewardRates.length != time.length
        ) {
            revert InvalidScenario();
        }

        mockSimpleMainRewarder();
        for (uint256 i = 0; i < rewardRates.length; i++) {
            mockRewardRate(mainRewarder, rewardRates[i]);
            mockTotalSupply(mainRewarder, totalSupply[i]);
            mockRewardPerToken(mainRewarder, rewardPerToken[i]);

            calculator.snapshot();
            vm.warp(block.timestamp + time[i]);
        }
    }

    function create2StepsSnapshotWithTotalSupplyIncrease(
        uint256 moveForwardInTime
    ) internal {
        mockSimpleMainRewarder();
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        mockTotalSupply(mainRewarder, TOTAL_SUPPLY + ((TOTAL_SUPPLY * 30) / 100));

        calculator.snapshot();

        vm.warp(block.timestamp + moveForwardInTime);
    }
}

contract ShouldSnapshot is ConvexCalculatorTest {
    function test_ReturnsTrueIfNoSnapshotTakenYet() public {
        mockSimpleMainRewarder();
        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSnapshotTakenWithinInterval() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfExtraRewardsAdded() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        addMockExtraRewarder();

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfRewardRatesChangedMidProcess() public {
        mockSimpleMainRewarder();

        calculator.snapshot();

        mockRewardRate(mainRewarder, REWARD_RATE + 10);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfSnapshotTakenBeforeInterval() public {
        mockSimpleMainRewarder();

        assertTrue(calculator.shouldSnapshot());

        calculator.snapshot();

        assertFalse(calculator.shouldSnapshot());

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSnapshotTakenWithin24Hours() public {
        create2StepsSnapshot();

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfNoSnapshotTakenIn24Hours() public {
        create2StepsSnapshot();

        vm.warp(block.timestamp + 25 hours);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfRewardPeriodFinished() public {
        create2StepsSnapshot();

        mockPeriodFinish(mainRewarder, block.timestamp - 1);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfRewardRateIsZero() public {
        create2StepsSnapshot();

        mockRewardRate(mainRewarder, 0);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfTotalSupplyIsZero() public {
        create2StepsSnapshot();

        mockTotalSupply(mainRewarder, 0);

        assertTrue(calculator.shouldSnapshot());
    }

    function test_ReturnsFalseIfSupplyDiffersBy5PctAndSnapshotTakenWithin8Hours() public {
        create2StepsSnapshotWithTotalSupplyIncrease(5 hours);

        assertFalse(calculator.shouldSnapshot());
    }

    function test_ReturnsTrueIfSupplyDiffersBy5PctAndSnapshotTakenAfter8Hours() public {
        create2StepsSnapshotWithTotalSupplyIncrease(9 hours);

        assertTrue(calculator.shouldSnapshot());
    }
}

contract Snapshot is ConvexCalculatorTest {
    function test_StartsSnapshotProcess() public {
        uint256 currentTime = block.timestamp;
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        assertTrue(calculator.lastSnapshotRewardPerToken(mainRewarder) == REWARD_PER_TOKEN + 1);
        assertTrue(calculator.lastSnapshotTimestamps(mainRewarder) == currentTime);
        assertTrue(calculator.safeTotalSupplies(mainRewarder) == 0);
    }

    function test_RevertIf_PriceIsntSafe() public {
        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, false)
        );

        mockSimpleMainRewarder();

        vm.expectRevert(abi.encodeWithSelector(Errors.UnsafePrice.selector, lpToken, 1, 1));
        calculator.snapshot();
    }

    function test_FinalizesSnapshotProcess() public {
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();

        // should reset the lastSnapshotRewardPerToken
        assertTrue(calculator.lastSnapshotRewardPerToken(mainRewarder) == 0);
        assertTrue(calculator.lastSnapshotTimestamps(mainRewarder) == block.timestamp);
    }
}

contract Current is ConvexCalculatorTest {
    function test_FinalizesSnapshotProcess() public {
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();
    }

    function test_RevertIf_PriceIsntSafe() public {
        mockSimpleMainRewarder();

        // start the snapshot process
        calculator.snapshot();

        // move forward in time
        vm.warp(block.timestamp + 5 hours);

        calculator.snapshot();

        vm.mockCall(
            rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector), abi.encode(1, 1, false)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.UnsafePrice.selector, lpToken, 1, 1));
        calculator.current();
    }

    function test_IncreaseIncentiveCredits() public {
        uint256 nbSnapshots = 6;
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);

        uint256 rewardPerTokenValue = 40_000_000_000_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14_000_000_000_000_000;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 7 hours;
            }

            rewardPerTokenValue += 5_000_000_000_000_000_000;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        // 12 credits are earned per day
        assertEq(res.stakingIncentiveStats.incentiveCredits, nbSnapshots * 6);
        assertEq(res.stakingIncentiveStats.rewardTokens.length, 2);

        assertEq(res.stakingIncentiveStats.rewardTokens[0], mainRewarderRewardToken);
        assertEq(res.stakingIncentiveStats.rewardTokens[1], platformRewarder);

        assertTrue(res.stakingIncentiveStats.periodFinishForRewards[0] > PERIOD_FINISH_IN);
        assertTrue(res.stakingIncentiveStats.periodFinishForRewards[1] > PERIOD_FINISH_IN);
    }

    function test_DecreaseIncentiveCredits() public {
        uint256 nbSnapshots = 24;
        uint256[] memory rewardRates = new uint256[](nbSnapshots);
        uint256[] memory totalSupply = new uint256[](nbSnapshots);
        uint256[] memory rewardPerToken = new uint256[](nbSnapshots);
        uint256[] memory time = new uint256[](nbSnapshots);

        uint256 rewardPerTokenValue = 40_000_000_000_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = 14_000_000_000_000_000;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // every 2 snapshots, set time to 1 day
            if (i % 2 == 0) {
                time[i] = 1 days;
            } else {
                time[i] = 8 hours;
            }

            rewardPerTokenValue += 5_000_000_000_000_000_000;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);

        IDexLSTStats.DexLSTStatsData memory res = calculator.current();

        // Ensure that the incentive credits have been increased
        assertTrue(res.stakingIncentiveStats.incentiveCredits == 24 * 6);

        // Decrease the incentive credits by decreasing the reward rate
        nbSnapshots = 3;
        rewardRates = new uint256[](nbSnapshots);
        totalSupply = new uint256[](nbSnapshots);
        rewardPerToken = new uint256[](nbSnapshots);
        time = new uint256[](nbSnapshots);

        uint256 rewardRatesValue = 1_000_000_000;
        for (uint256 i = 0; i < nbSnapshots; i++) {
            rewardRates[i] = rewardRatesValue;
            totalSupply[i] = 18_000_000_000_000_000_000_000;
            rewardPerToken[i] = rewardPerTokenValue;

            // 24 hours of decay in 8 hours increments
            // last 8 hours of credit are burned in current()
            time[i] = 8 hours;

            rewardRatesValue -= 5_000_000;
        }

        _runScenario(rewardRates, totalSupply, rewardPerToken, time);
        res = calculator.current();
        // Credits should go from 144 to 120 due to decay
        assertTrue(res.stakingIncentiveStats.incentiveCredits == 120);
    }

    function test_SafeTotalSupplies_UpdatedWhenPeriodFinishNotExpired() public {
        mockSimpleMainRewarder();
        calculator.snapshot();
        // move forward in time
        vm.warp(block.timestamp + 5 hours);
        // some reward have accumulated
        mockRewardPerToken(mainRewarder, REWARD_PER_TOKEN + 1);
        mockPeriodFinish(mainRewarder, block.timestamp + 7 days);
        mockRewardToken(mainRewarder, mainRewarderRewardToken);
        calculator.snapshot();
        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertEq(calculator.safeTotalSupplies(mainRewarder), 18e25);
        assertEq(res.stakingIncentiveStats.safeTotalSupply, 18e25);
    }

    function test_SafeTotalSupplies_NotUpdatedWhenPeriodFinishExpired() public {
        mockSimpleMainRewarder();
        calculator.snapshot();
        // move forward in time
        vm.warp(block.timestamp + 5 hours);
        // some reward have accumulated
        mockRewardPerToken(mainRewarder, REWARD_PER_TOKEN + 1);
        mockPeriodFinish(mainRewarder, block.timestamp);
        mockRewardToken(mainRewarder, mainRewarderRewardToken);
        calculator.snapshot();
        IDexLSTStats.DexLSTStatsData memory res = calculator.current();
        assertEq(calculator.safeTotalSupplies(mainRewarder), 0);
        assertEq(res.stakingIncentiveStats.safeTotalSupply, 0);
    }
}

contract ResolveRewardToken is ConvexCalculatorTest {
    function test_ResolvesCorrectRewardToken_AndUnwrapsStashToken_WithPidLessThan151() public {
        mockSimpleMainRewarder(25);

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        calculator.snapshot();

        addMockExtraRewarder();

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        calculator.snapshot();

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (extraRewarderRewardToken, PRICE_STALE_CHECK))
        );
        calculator.current();
    }

    function test_ResolvesCorrectRewardToken_AndUnwrapsStashToken_WithPidMoreThan151() public {
        mockSimpleMainRewarder(152);

        address rewardToken = vm.addr(152);
        vm.label(rewardToken, "rewardToken");
        vm.mockCall(rewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        mockIsInvalid(extraRewarderRewardToken, false);
        mockToken(extraRewarderRewardToken, rewardToken);

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        calculator.snapshot();

        addMockExtraRewarder();

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        vm.expectCall(
            address(pricingStats), abi.encodeCall(IIncentivesPricingStats.getPrice, (rewardToken, PRICE_STALE_CHECK))
        );
        calculator.snapshot();

        vm.expectCall(
            address(pricingStats),
            abi.encodeCall(IIncentivesPricingStats.getPrice, (mainRewarderRewardToken, PRICE_STALE_CHECK))
        );
        vm.expectCall(
            address(pricingStats), abi.encodeCall(IIncentivesPricingStats.getPrice, (rewardToken, PRICE_STALE_CHECK))
        );
        calculator.current();
    }

    function test_ResolveRewardToken_WithPidLessThan151() public {
        // Get a valid rewarder
        IBaseRewardPool rewarder = IBaseRewardPool(0x0A760466E1B4621579a82a39CB56Dda2F4E70f03);
        assert(rewarder.pid() < 151);
        assert(rewarder.extraRewardsLength() > 0);

        // Get the first extra rewarder
        address extraRewarder = rewarder.extraRewards(0);
        assertEq(extraRewarder, 0x008aEa5036b819B4FEAEd10b2190FBb3954981E8);

        // Check the stash token
        address expectedRewardToken = address(IBaseRewardPool(extraRewarder).rewardToken());
        assertEq(expectedRewardToken, LDO_MAINNET);

        // Mock base rewarder
        vm.mockCall(mainRewarder, abi.encodeWithSelector(IBaseRewardPool.pid.selector), abi.encode(25));

        address rewardToken = calculator.resolveRewardToken(extraRewarder);

        // Verify the reward token
        assertEq(rewardToken, expectedRewardToken);
    }

    function test_ResolveRewardToken_WithPidMoreThan151() public {
        // Get a valid rewarder
        IBaseRewardPool rewarder = IBaseRewardPool(0x1A3c8B2F89B1C2593fa46C30ADA0b4E3D0133fF8);
        assert(rewarder.pid() >= 151);
        assert(rewarder.extraRewardsLength() > 0);

        // Get the first extra rewarder
        address extraRewarder = rewarder.extraRewards(0);
        assertEq(extraRewarder, 0xB83607472704FE3bCf6165EB6ff1941722b3C8B6);

        // Check the stash token
        ITokenWrapper stashToken = ITokenWrapper(address(IBaseRewardPool(extraRewarder).rewardToken()));
        assertEq(address(stashToken), 0xF132a783d8567c11D3Df3e4Ef890786AFFc16402);

        // Mock base rewarder
        vm.mockCall(mainRewarder, abi.encodeWithSelector(IBaseRewardPool.pid.selector), abi.encode(152));

        address rewardToken = calculator.resolveRewardToken(extraRewarder);

        // Unwrap the reward token
        assertEq(rewardToken, stashToken.token());
        assertEq(rewardToken, CNC_MAINNET);
    }

    function test_ResolveInvalidRewardToken_ReturnsZeroAddress() public {
        // Get a valid rewarder
        IBaseRewardPool rewarder = IBaseRewardPool(0x1A3c8B2F89B1C2593fa46C30ADA0b4E3D0133fF8);
        assert(rewarder.pid() >= 151);
        assert(rewarder.extraRewardsLength() > 0);

        // Get the first extra rewarder
        address extraRewarder = rewarder.extraRewards(0);
        assertEq(extraRewarder, 0xB83607472704FE3bCf6165EB6ff1941722b3C8B6);

        // Check the stash token
        ITokenWrapper stashToken = ITokenWrapper(address(IBaseRewardPool(extraRewarder).rewardToken()));
        assertEq(address(stashToken), 0xF132a783d8567c11D3Df3e4Ef890786AFFc16402);

        // Mock token to be invalid
        mockIsInvalid(address(stashToken), true);

        // Mock base rewarder
        vm.mockCall(mainRewarder, abi.encodeWithSelector(IBaseRewardPool.pid.selector), abi.encode(152));

        address rewardToken = calculator.resolveRewardToken(extraRewarder);

        // Unwrap the reward token
        assertEq(rewardToken, address(0));
    }
}

contract IncentiveAprScalingWithDecimals is ConvexCalculatorTest {
    function test_ExpectedIncentiveAprMainRewarder_18DecimalsExtraRewards() public {
        mockSimpleMainRewarder();
        addMockExtraRewarder();
        address rewardToken = vm.addr(152);
        vm.label(rewardToken, "rewardToken");
        vm.mockCall(rewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        mockIsInvalid(extraRewarderRewardToken, false);
        mockToken(extraRewarderRewardToken, rewardToken);

        uint256 rewardRate18Decimals = uint256(1e18) / 365 days; // 31709791983 ; //  1 WETH per year
        uint256 expectedSafeTotalSupply = 100e18;
        uint256 startingRewardPerToken = 1e18;
        // 4566210045552 over 4 hours implies safeTotalSupply == 100e18 if reward rate == 31709791983
        uint256 endingRewardPerToken = 1e18 + 4_566_210_045_552;

        mockRewardRate(mainRewarder, 0);
        mockRewardPerToken(extraRewarder1, startingRewardPerToken);
        mockRewardRate(extraRewarder1, rewardRate18Decimals);
        calculator.snapshot();
        vm.warp(block.timestamp + 4 hours);
        mockRewardPerToken(extraRewarder1, endingRewardPerToken);
        calculator.snapshot();
        assertEq(calculator.safeTotalSupplies(extraRewarder1), expectedSafeTotalSupply);
        assertApproxEqAbs(calculator.lastSnapshotTotalAPR(), 1e16, 1e8); // 1e8 accounts for rounding
    }

    function test_ExpectedIncentiveAprMainRewarder_6DecimalsExtraRewards() public {
        mockSimpleMainRewarder();
        addMockExtraRewarder();
        address rewardToken = vm.addr(152);
        vm.label(rewardToken, "rewardToken");
        vm.mockCall(rewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
        mockIsInvalid(extraRewarderRewardToken, false);
        mockToken(extraRewarderRewardToken, rewardToken);

        uint256 rewardRate6Decimals = uint256(100e6) / 365 days; // 3 ;  //  ~100 USDC per year
        uint256 expectedSafeTotalSupply = 100e18;
        uint256 startingRewardPerToken = 1e18;
        // 432 over 4 hours implies safeTotalSupply == 100e18 if reward rate == 3
        uint256 endingRewardPerToken = 1e18 + 432;

        mockRewardRate(mainRewarder, 0);
        mockRewardPerToken(extraRewarder1, startingRewardPerToken);
        mockRewardRate(extraRewarder1, rewardRate6Decimals);
        calculator.snapshot();
        vm.warp(block.timestamp + 4 hours);
        mockRewardPerToken(extraRewarder1, endingRewardPerToken);
        calculator.snapshot();
        assertEq(calculator.safeTotalSupplies(extraRewarder1), expectedSafeTotalSupply);
        // 946_080_000_000_000_000 instead of 100e16 because of the resolution lost when going from
        // 31709791983 -> 3
        assertEq(calculator.lastSnapshotTotalAPR(), 946_080_000_000_000_000);
    }

    function test_RewardRateOverflow() public {
        mockSimpleMainRewarder();
        addMockExtraRewarder();
        address rewardToken = vm.addr(152);
        vm.label(rewardToken, "rewardToken");
        vm.mockCall(rewardToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
        mockIsInvalid(extraRewarderRewardToken, false);
        mockToken(extraRewarderRewardToken, rewardToken);

        vm.mockCall(
            pricingStats, abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector), abi.encode(1e18, 1e18)
        );

        vm.mockCall(rootPriceOracle, abi.encodeWithSelector(IRootPriceOracle.getPriceInEth.selector), abi.encode(1e18));
        vm.mockCall(
            rootPriceOracle,
            abi.encodeWithSelector(IRootPriceOracle.getRangePricesLP.selector),
            abi.encode(1e18, 1e18, true)
        );

        mockRewardRate(mainRewarder, 0);
        mockRewardPerToken(extraRewarder1, 1e18);
        uint256 largestRewardRateIfTokenPriceIs1e18 = (2 ** 256 - 1) / (1e54 * Stats.SECONDS_IN_YEAR);

        assertEq(largestRewardRateIfTokenPriceIs1e18, 3_671_743_063_080_802);
        mockRewardRate(extraRewarder1, largestRewardRateIfTokenPriceIs1e18);
        calculator.snapshot();
        // trigger another snapshot early because the rewardRate changes
        mockRewardRate(extraRewarder1, largestRewardRateIfTokenPriceIs1e18 + 1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        calculator.snapshot();

        uint256 largestRewardRateIfTokenPriceIs1 = (2 ** 256 - 1) / (1e36 * Stats.SECONDS_IN_YEAR);
        vm.mockCall(pricingStats, abi.encodeWithSelector(IIncentivesPricingStats.getPrice.selector), abi.encode(1, 1));
        mockRewardRate(extraRewarder1, largestRewardRateIfTokenPriceIs1);
        assertTrue(calculator.shouldSnapshot());
        calculator.snapshot();
        mockRewardRate(extraRewarder1, largestRewardRateIfTokenPriceIs1 + 1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        calculator.snapshot();
    }
}

contract Initialize is ConvexCalculatorTest {
    function test_RevertIf_RewarderLpTokenDoesntMatchProvided() public {
        address invalidLpToken = makeAddr("invalidLpToken");

        ConvexCalculator calc =
            ConvexCalculator(Clones.clone(address(new ConvexCalculator(ISystemRegistry(systemRegistry), booster))));

        bytes32[] memory dependantAprs = new bytes32[](0);
        IncentiveCalculatorBase.InitData memory initData = IncentiveCalculatorBase.InitData({
            rewarder: mainRewarder,
            underlyerStats: underlyerStats,
            platformToken: platformRewarder,
            lpToken: invalidLpToken,
            pool: pool
        });
        bytes memory encodedInitData = abi.encode(initData);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "convexResolvedLpToken"));
        calc.initialize(dependantAprs, encodedInitData);
    }
}
