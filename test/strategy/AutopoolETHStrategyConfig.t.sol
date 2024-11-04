// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { NavTracking } from "src/strategy/NavTracking.sol";
import { AutopoolETHStrategyConfig } from "src/strategy/AutopoolETHStrategyConfig.sol";
import { AutopoolETHStrategyTestHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";

contract AutopoolETHStrategyConfigTest is Test {
    function test_defaultTestConfigPasses() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetInitInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.minInDays = 7;
        config.swapCostOffset.initInDays = 7;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.initInDays = 6;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetInitInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.initInDays = 90;
        config.swapCostOffset.maxInDays = 90;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.initInDays = 91;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetTightenThresholdInViolations_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.tightenThresholdInViolations = 1;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.tightenThresholdInViolations = 0;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetTightenThresholdInViolations_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.tightenThresholdInViolations = 10;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.tightenThresholdInViolations = 11;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetTightenStepInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.tightenStepInDays = 1;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.tightenStepInDays = 0;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetTightenStepInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.tightenStepInDays = 7;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.tightenStepInDays = 8;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetRelaxThresholdInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.relaxThresholdInDays = 14;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.relaxThresholdInDays = 13;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetRelaxThresholdInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.relaxThresholdInDays = 90;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.relaxThresholdInDays = 91;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetRelaxStepInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.relaxStepInDays = 1;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.relaxStepInDays = 0;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetRelaxStepInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.relaxStepInDays = 7;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.relaxStepInDays = 8;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetMaxInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.initInDays = 7;
        config.swapCostOffset.minInDays = 7;
        config.swapCostOffset.maxInDays = 8;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.maxInDays = 7;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetMaxInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.maxInDays = 90;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.maxInDays = 91;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetMaxInDays_GreaterThanMin() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.initInDays = 70;
        config.swapCostOffset.maxInDays = 70;
        config.swapCostOffset.minInDays = 69;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.minInDays = 70;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_swapCostOffsetMinInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.swapCostOffset.minInDays = 7;
        AutopoolETHStrategyConfig.validate(config);

        config.swapCostOffset.minInDays = 6;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_navLookback_1LessThan2() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.navLookback.lookback1InDays = 31;
        config.navLookback.lookback2InDays = 32;
        AutopoolETHStrategyConfig.validate(config);

        config.navLookback.lookback1InDays = 31;
        config.navLookback.lookback2InDays = 31;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_navLookback_2LessThan3() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.navLookback.lookback2InDays = 51;
        config.navLookback.lookback3InDays = 52;
        AutopoolETHStrategyConfig.validate(config);

        config.navLookback.lookback2InDays = 51;
        config.navLookback.lookback3InDays = 51;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_navLookback_LessThanMax() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        AutopoolETHStrategyConfig.validate(config);

        config.navLookback.lookback1InDays = NavTracking.MAX_NAV_TRACKING;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);

        config.navLookback.lookback2InDays = NavTracking.MAX_NAV_TRACKING;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);

        config.navLookback.lookback3InDays = NavTracking.MAX_NAV_TRACKING;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_slippageMaxNormalOperationSlippage() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.slippage.maxNormalOperationSlippage = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.slippage.maxNormalOperationSlippage += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_slippageMaxTrimOperationSlippage() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.slippage.maxTrimOperationSlippage = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.slippage.maxTrimOperationSlippage += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_slippageMaxEmergencyOperationSlippage() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.slippage.maxEmergencyOperationSlippage = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.slippage.maxEmergencyOperationSlippage += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_slippageMaxShutdownOperationSlippage() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.slippage.maxShutdownOperationSlippage = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.slippage.maxShutdownOperationSlippage += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsBaseYield_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.baseYield = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsBaseYield_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.baseYield = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.baseYield += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsFeeYield_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.feeYield = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsFeeYield_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.feeYield = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.feeYield += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsIncentiveYield_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.incentiveYield = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsIncentiveYield_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.incentiveYield = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.incentiveYield += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPriceDiscountExit_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.priceDiscountExit = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPriceDiscountExit_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.priceDiscountExit = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.priceDiscountExit += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPriceDiscountEnter_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.priceDiscountEnter = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPriceDiscountEnter_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.priceDiscountEnter = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.priceDiscountEnter += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPricePremium_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.pricePremium = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_modelWeightsPricePremium_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.modelWeights.pricePremium = 1e6;
        AutopoolETHStrategyConfig.validate(config);

        config.modelWeights.pricePremium += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_PauseRebalancePeriodInDays_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.pauseRebalancePeriodInDays = 7;
        AutopoolETHStrategyConfig.validate(config);

        config.pauseRebalancePeriodInDays = 6;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_PauseRebalancePeriodInDays_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.pauseRebalancePeriodInDays = 90;
        AutopoolETHStrategyConfig.validate(config);

        config.pauseRebalancePeriodInDays = 91;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_rebalanceTimeGapInSeconds_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.rebalanceTimeGapInSeconds = 1 hours;
        AutopoolETHStrategyConfig.validate(config);

        config.rebalanceTimeGapInSeconds -= 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_rebalanceTimeGapInSeconds_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.rebalanceTimeGapInSeconds = 30 days;
        AutopoolETHStrategyConfig.validate(config);

        config.rebalanceTimeGapInSeconds += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxPremium_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxPremium = 0;
        AutopoolETHStrategyConfig.validate(config);

        config.maxPremium -= 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxPremium_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxPremium = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.maxPremium += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxDiscount_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxDiscount = 0;
        AutopoolETHStrategyConfig.validate(config);

        config.maxDiscount -= 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxDiscount_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxDiscount = 0.25e18;
        AutopoolETHStrategyConfig.validate(config);

        config.maxDiscount += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_staleDataToleranceInSeconds_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.staleDataToleranceInSeconds = 1 hours;
        AutopoolETHStrategyConfig.validate(config);

        config.staleDataToleranceInSeconds -= 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_staleDataToleranceInSeconds_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.staleDataToleranceInSeconds = 7 days;
        AutopoolETHStrategyConfig.validate(config);

        config.staleDataToleranceInSeconds += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxAllowedDiscount_Min() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxAllowedDiscount = 0;
        AutopoolETHStrategyConfig.validate(config);

        config.maxAllowedDiscount -= 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_maxAllowedDiscount_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.maxAllowedDiscount = 0.5e18;
        AutopoolETHStrategyConfig.validate(config);

        config.maxAllowedDiscount += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_lstPriceGapTolerance_AllowsZero() public pure {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.lstPriceGapTolerance = 0;
        AutopoolETHStrategyConfig.validate(config);
    }

    function test_lstPriceGapTolerance_Max() public {
        AutopoolETHStrategyConfig.StrategyConfig memory config = AutopoolETHStrategyTestHelpers.getDefaultConfig();

        config.lstPriceGapTolerance = 500;
        AutopoolETHStrategyConfig.validate(config);

        config.lstPriceGapTolerance += 1;
        vm.expectRevert();
        AutopoolETHStrategyConfig.validate(config);
    }
}
