// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import {
    BAL_VAULT,
    RSWETH_MAINNET,
    EZETH_MAINNET,
    WEETH_MAINNET,
    OSETH_MAINNET,
    WETH_MAINNET,
    USDC_MAINNET,
    GHO_MAINNET,
    USDT_MAINNET,
    RETH_MAINNET
} from "test/utils/Addresses.sol";

import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISpotPriceOracle } from "src/interfaces/oracles/ISpotPriceOracle.sol";

import { BalancerV2ComposableStableMathOracle } from "src/oracles/providers/BalancerV2ComposableStableMathOracle.sol";
import { BalancerV2MetaStableMathOracle } from "src/oracles/providers/BalancerV2MetaStableMathOracle.sol";

/**
 * @dev Some notes on what is going on here, will help with understanding what is going on here.
 *
 * First, a note on nomenclature in this file.  Original, old, and batch swap all refer to the original BalV2 oracles,
 * which relies on querying the vault for the result of a swap.  New and StableMath oracles refers to the new oracle
 * functionality, which leverages the underlying Stable Math in Bal Stable pools.
 *
 * This test file used queries to the old oracles to get prices and pricing info.  These queries have been deleted and
 * the values hardcoded to reduce our dependencies in test files to these contracts, as they may be removed from this
 * repo eventually.
 *
 * Individual functionalities for the Meta and Composable pools were testing in individual unit testing files, this
 * test is meant to mostly check the underlying math in the `BaseBalancerStableMathOracle.sol` file in the context of
 * BalancerV2 pools.  This is why both Composable and Meta pool oracles are tested here.
 *
 * The goal was to have pools that would take into account decimal and rate scaling in all circumstances, as there
 * is a decent amount of logic dealing with this in the code written vs the StableMath library code that was copied
 * directly from Balancer.
 *
 * The price is not expected to be exact between methods, as of right now a 5bps variance is being checked for.  This
 * is quite tight and may not hold up across all scenarios.
 */
contract BalV2StableMathOracleIntegration is Test {
    // Composable pools
    address public constant OSETH_WETH_COMP = 0xDACf5Fa19b1f720111609043ac67A9818262850c;
    address public constant GHO_USDC_USDT_COMP = 0x8353157092ED8Be69a9DF8F95af097bbF33Cb2aF;
    address public constant WEETH_EZETH_RSWETH_COMP = 0x848a5564158d84b8A8fb68ab5D004Fae11619A54;

    // Meta pools
    address public constant RETH_WETH_META = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

    BalancerV2ComposableStableMathOracle public composableOracle;
    BalancerV2MetaStableMathOracle public metaOracle;

    ISystemRegistry public registry;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_229_701);

        // Registry and root price oracle not actually used here, so using mocks
        registry = ISystemRegistry(makeAddr("registry"));
        vm.mockCall(address(registry), abi.encodeCall(ISystemRegistry.rootPriceOracle, ()), abi.encode(address(1)));

        composableOracle = new BalancerV2ComposableStableMathOracle(IVault(BAL_VAULT), registry);
        metaOracle = new BalancerV2MetaStableMathOracle(IVault(BAL_VAULT), registry);
    }

    // Checking that new price is within 5 bps of old price
    function _checkVariance(uint256 querySwapPrice, uint256 stableMathPrice) internal {
        // Function checks that first two values are within third value of each other, where 1e18 is 100%
        // for the third value.  See https://book.getfoundry.sh/reference/forge-std/assertApproxEqRel
        // Examples of relationship between number in e18, percentage and bps below:
        // - 1e18 = 100% = 10_000bps
        // - .01e18 = 1% = 100bps
        // - .0001e18 = .01% = 1bps
        assertApproxEqRel(stableMathPrice, querySwapPrice, 0.0005e18);
    }
}

contract ComposableStableMathOracleTest is BalV2StableMathOracleIntegration {
    function test_getSpotPrice() public {
        //
        // OSETH / WETH pool tests
        //

        // Query batch swap (old) method - 1032541828996240624
        // StableMath (new) method -       1032519297977648151
        uint256 originalMethodPrice = 1_032_541_828_996_240_624;
        (uint256 spot, address actualQuote) =
            composableOracle.getSpotPrice(OSETH_MAINNET, OSETH_WETH_COMP, WETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, WETH_MAINNET);

        // Query batch swap (old) method - 968483765771087108
        // StableMath (new) method -       968503799810177688
        originalMethodPrice = 968_483_765_771_087_108;
        (spot, actualQuote) = composableOracle.getSpotPrice(WETH_MAINNET, OSETH_WETH_COMP, OSETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, OSETH_MAINNET);

        //
        // GHO / USDC / USDT pool tests
        //

        // Query batch swap (old) method - 998499
        // StableMath (new) method -       998576
        originalMethodPrice = 998_499;
        (spot, actualQuote) = composableOracle.getSpotPrice(USDC_MAINNET, GHO_USDC_USDT_COMP, USDT_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, USDT_MAINNET);

        // Query batch swap (old) method - 1013202501135057028
        // StableMath (new) method -       1013202492493128124
        originalMethodPrice = 1_013_202_501_135_057_028;
        (spot, actualQuote) = composableOracle.getSpotPrice(USDC_MAINNET, GHO_USDC_USDT_COMP, GHO_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, GHO_MAINNET);

        // Query batch swap (old) method - 1014646715119662431
        // StableMath (new) method -       1014646704622875155
        originalMethodPrice = 1_014_646_715_119_662_431;
        (spot, actualQuote) = composableOracle.getSpotPrice(USDT_MAINNET, GHO_USDC_USDT_COMP, GHO_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, GHO_MAINNET);

        // Query batch swap (old) method - 1001400
        // StableMath (new) method -       1001425
        originalMethodPrice = 1_001_400;
        (spot, actualQuote) = composableOracle.getSpotPrice(USDT_MAINNET, GHO_USDC_USDT_COMP, USDC_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, USDC_MAINNET);

        // Query batch swap (old) method - 986493
        // StableMath (new) method -       986969
        originalMethodPrice = 986_493;
        (spot, actualQuote) = composableOracle.getSpotPrice(GHO_MAINNET, GHO_USDC_USDT_COMP, USDC_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, USDC_MAINNET);

        // Query batch swap (old) method - 985492
        // StableMath (new) method -       985564
        originalMethodPrice = 985_492;
        (spot, actualQuote) = composableOracle.getSpotPrice(GHO_MAINNET, GHO_USDC_USDT_COMP, USDT_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, USDT_MAINNET);

        //
        // WEETH / EZETH / RSWETH pool tests
        //

        // Query batch swap (old) method - 973973920855865346
        // StableMath (new) method -       973948586538712354
        originalMethodPrice = 973_973_920_855_865_346;
        (spot, actualQuote) = composableOracle.getSpotPrice(EZETH_MAINNET, WEETH_EZETH_RSWETH_COMP, WEETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, WEETH_MAINNET);

        // Query batch swap (old) method - 1008064604537272909
        // StableMath (new) method -       1008048506631870729
        originalMethodPrice = 1_008_064_604_537_272_909;
        (spot, actualQuote) = composableOracle.getSpotPrice(EZETH_MAINNET, WEETH_EZETH_RSWETH_COMP, RSWETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, RSWETH_MAINNET);

        // Query batch swap (old) method - 1035001604415945378
        // StableMath (new) method -       1034977332317187325
        originalMethodPrice = 1_035_001_604_415_945_378;
        (spot, actualQuote) = composableOracle.getSpotPrice(WEETH_MAINNET, WEETH_EZETH_RSWETH_COMP, RSWETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, RSWETH_MAINNET);

        // Query batch swap (old) method - 1026721481838909563
        // StableMath (new) method -       1026694110264159149
        originalMethodPrice = 1_026_721_481_838_909_563;
        (spot, actualQuote) = composableOracle.getSpotPrice(WEETH_MAINNET, WEETH_EZETH_RSWETH_COMP, EZETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, EZETH_MAINNET);

        // Query batch swap (old) method - 991999881356880752
        // StableMath (new) method -       991984101476685544
        originalMethodPrice = 991_999_881_356_880_752;
        (spot, actualQuote) = composableOracle.getSpotPrice(RSWETH_MAINNET, WEETH_EZETH_RSWETH_COMP, EZETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, EZETH_MAINNET);

        // Query batch swap (old) method - 966182032443141256
        // StableMath (new) method -       966160025026744574
        originalMethodPrice = 966_182_032_443_141_256;
        (spot, actualQuote) = composableOracle.getSpotPrice(RSWETH_MAINNET, WEETH_EZETH_RSWETH_COMP, WEETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, WEETH_MAINNET);
    }

    function test_getSafeSpotPriceInfo() public {
        // Setting these to allow data to be filled in from original oracle method (query batch swap on vault).
        uint256 totalSupplyOriginalMethod;
        ISpotPriceOracle.ReserveItemInfo[] memory reservesOriginalMethod = new ISpotPriceOracle.ReserveItemInfo[](3);

        //
        // OSETH / WETH pool
        //
        (uint256 totalSupplyNewMethod, ISpotPriceOracle.ReserveItemInfo[] memory reservesNewMethod) =
            composableOracle.getSafeSpotPriceInfo(OSETH_WETH_COMP, OSETH_WETH_COMP, WETH_MAINNET);

        // Fill out data from query swap oracles for comparison
        totalSupplyOriginalMethod = 17_814_086_512_982_154_167_476;
        reservesOriginalMethod[0] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            reserveAmount: 9_480_883_163_727_768_280_638,
            rawSpotPrice: 968_483_765_771_087_108,
            actualQuoteToken: 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38
        });
        reservesOriginalMethod[1] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38,
            reserveAmount: 8_310_269_417_439_486_253_403,
            rawSpotPrice: 1_032_541_828_996_240_624,
            actualQuoteToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        });

        // checks
        assertEq(totalSupplyOriginalMethod, totalSupplyNewMethod);

        assertEq(reservesNewMethod[0].token, reservesOriginalMethod[0].token);
        assertEq(reservesNewMethod[0].reserveAmount, reservesOriginalMethod[0].reserveAmount);
        _checkVariance(reservesOriginalMethod[0].rawSpotPrice, reservesNewMethod[0].rawSpotPrice);
        assertEq(reservesNewMethod[0].actualQuoteToken, reservesOriginalMethod[0].actualQuoteToken);

        assertEq(reservesNewMethod[1].token, reservesOriginalMethod[1].token);
        assertEq(reservesNewMethod[1].reserveAmount, reservesOriginalMethod[1].reserveAmount);
        _checkVariance(reservesOriginalMethod[1].rawSpotPrice, reservesNewMethod[1].rawSpotPrice);
        assertEq(reservesNewMethod[1].actualQuoteToken, reservesOriginalMethod[1].actualQuoteToken);

        //
        // GHO / USDC / USDT pool
        //

        // Query to StableMath oracle
        (totalSupplyNewMethod, reservesNewMethod) =
            composableOracle.getSafeSpotPriceInfo(GHO_USDC_USDT_COMP, GHO_USDC_USDT_COMP, USDC_MAINNET);

        // Data queried from original oracle method
        totalSupplyOriginalMethod = 16_754_165_660_143_280_212_648_514;
        reservesOriginalMethod[0] = ISpotPriceOracle.ReserveItemInfo({
            token: 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f,
            reserveAmount: 14_058_154_600_539_093_852_917_519,
            rawSpotPrice: 986_493,
            actualQuoteToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        });
        reservesOriginalMethod[1] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            reserveAmount: 1_530_668_630_739,
            rawSpotPrice: 998_499,
            actualQuoteToken: 0xdAC17F958D2ee523a2206206994597C13D831ec7
        });
        reservesOriginalMethod[2] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
            reserveAmount: 1_394_713_400_712,
            rawSpotPrice: 1_001_400,
            actualQuoteToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        });

        // Checks against original oracle data
        assertEq(totalSupplyOriginalMethod, totalSupplyNewMethod);

        assertEq(reservesNewMethod[0].token, reservesOriginalMethod[0].token);
        assertEq(reservesNewMethod[0].reserveAmount, reservesOriginalMethod[0].reserveAmount);
        _checkVariance(reservesOriginalMethod[0].rawSpotPrice, reservesNewMethod[0].rawSpotPrice);
        assertEq(reservesNewMethod[0].actualQuoteToken, reservesOriginalMethod[0].actualQuoteToken);

        assertEq(reservesNewMethod[1].token, reservesOriginalMethod[1].token);
        assertEq(reservesNewMethod[1].reserveAmount, reservesOriginalMethod[1].reserveAmount);
        _checkVariance(reservesOriginalMethod[1].rawSpotPrice, reservesNewMethod[1].rawSpotPrice);
        assertEq(reservesNewMethod[1].actualQuoteToken, reservesOriginalMethod[1].actualQuoteToken);

        assertEq(reservesNewMethod[2].token, reservesOriginalMethod[2].token);
        assertEq(reservesNewMethod[2].reserveAmount, reservesOriginalMethod[2].reserveAmount);
        _checkVariance(reservesOriginalMethod[2].rawSpotPrice, reservesNewMethod[2].rawSpotPrice);
        assertEq(reservesNewMethod[2].actualQuoteToken, reservesOriginalMethod[2].actualQuoteToken);

        //
        // WEETH / EZETH / RSWETH pool
        //

        // Query to StableMath oracle
        (totalSupplyNewMethod, reservesNewMethod) =
            composableOracle.getSafeSpotPriceInfo(WEETH_EZETH_RSWETH_COMP, WEETH_EZETH_RSWETH_COMP, WEETH_MAINNET);

        // Data queried from original oracle for comparison
        totalSupplyOriginalMethod = 1_712_604_131_272_550_437_965;
        reservesOriginalMethod[0] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110,
            reserveAmount: 418_962_814_351_062_528_106,
            rawSpotPrice: 973_973_920_855_865_346,
            actualQuoteToken: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee
        });
        reservesOriginalMethod[1] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
            reserveAmount: 343_794_745_091_117_506_397,
            rawSpotPrice: 1_035_001_604_415_945_378,
            actualQuoteToken: 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0
        });
        reservesOriginalMethod[2] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0,
            reserveAmount: 935_455_892_890_072_808_851,
            rawSpotPrice: 966_182_032_443_141_256,
            actualQuoteToken: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee
        });

        // Checks against original data
        assertEq(totalSupplyOriginalMethod, totalSupplyNewMethod);

        assertEq(reservesNewMethod[0].token, reservesOriginalMethod[0].token);
        assertEq(reservesNewMethod[0].reserveAmount, reservesOriginalMethod[0].reserveAmount);
        _checkVariance(reservesOriginalMethod[0].rawSpotPrice, reservesNewMethod[0].rawSpotPrice);
        assertEq(reservesNewMethod[0].actualQuoteToken, reservesOriginalMethod[0].actualQuoteToken);

        assertEq(reservesNewMethod[1].token, reservesOriginalMethod[1].token);
        assertEq(reservesNewMethod[1].reserveAmount, reservesOriginalMethod[1].reserveAmount);
        _checkVariance(reservesOriginalMethod[1].rawSpotPrice, reservesNewMethod[1].rawSpotPrice);
        assertEq(reservesNewMethod[1].actualQuoteToken, reservesOriginalMethod[1].actualQuoteToken);

        assertEq(reservesNewMethod[2].token, reservesOriginalMethod[2].token);
        assertEq(reservesNewMethod[2].reserveAmount, reservesOriginalMethod[2].reserveAmount);
        _checkVariance(reservesOriginalMethod[2].rawSpotPrice, reservesNewMethod[2].rawSpotPrice);
        assertEq(reservesNewMethod[2].actualQuoteToken, reservesOriginalMethod[2].actualQuoteToken);
    }
}

/// @notice This contract does not test as many pools as the composable tests.  There are fewer MetaStable pools in
/// existence.  The underlying math is all the same and is inherited from `BaseBalancerStableMathOracle.sol`, and the
/// external functionalities in the derived MetaStable contracts are tested elsewhere so this should be okay.
contract MetaStableMathOracleTest is BalV2StableMathOracleIntegration {
    function test_getSpotPrice() public {
        //
        // RETH / WETH pool
        //

        // Query batch swap (old) method - 1118961018466641656
        // StableMath (new) method -       1118955837253750086
        uint256 originalMethodPrice = 1_118_961_018_466_641_656;
        (uint256 spot, address actualQuote) = metaOracle.getSpotPrice(RETH_MAINNET, RETH_WETH_META, WETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, WETH_MAINNET);

        // Query batch swap (old) method - 893686173799881952
        // StableMath (new) method -       893682475974985465
        originalMethodPrice = 893_686_173_799_881_952;
        (spot, actualQuote) = metaOracle.getSpotPrice(WETH_MAINNET, RETH_WETH_META, RETH_MAINNET);

        _checkVariance(originalMethodPrice, spot);
        assertEq(actualQuote, RETH_MAINNET);
    }

    function test_getSafeSpotPriceInfo() public {
        // Setting these to allow data to be filled in from original oracle method (query batch swap on vault).
        uint256 totalSupplyOriginalMethod;
        ISpotPriceOracle.ReserveItemInfo[] memory reservesOriginalMethod = new ISpotPriceOracle.ReserveItemInfo[](2);

        //
        // RETH / WETH pool
        //
        (uint256 totalSupplyNewMethod, ISpotPriceOracle.ReserveItemInfo[] memory reservesNewMethod) =
            metaOracle.getSafeSpotPriceInfo(RETH_WETH_META, RETH_WETH_META, WETH_MAINNET);

        // Fill out data from query swap oracles for comparison
        totalSupplyOriginalMethod = 9_293_846_950_546_888_639_097;
        reservesOriginalMethod[0] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xae78736Cd615f374D3085123A210448E74Fc6393,
            reserveAmount: 4_537_392_887_048_228_044_779,
            rawSpotPrice: 1_118_961_018_466_641_656,
            actualQuoteToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        });
        reservesOriginalMethod[1] = ISpotPriceOracle.ReserveItemInfo({
            token: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            reserveAmount: 4_557_022_330_148_141_415_965,
            rawSpotPrice: 893_686_173_799_881_952,
            actualQuoteToken: 0xae78736Cd615f374D3085123A210448E74Fc6393
        });

        // checks
        assertEq(totalSupplyOriginalMethod, totalSupplyNewMethod);

        assertEq(reservesNewMethod[0].token, reservesOriginalMethod[0].token);
        assertEq(reservesNewMethod[0].reserveAmount, reservesOriginalMethod[0].reserveAmount);
        _checkVariance(reservesOriginalMethod[0].rawSpotPrice, reservesNewMethod[0].rawSpotPrice);
        assertEq(reservesNewMethod[0].actualQuoteToken, reservesOriginalMethod[0].actualQuoteToken);

        assertEq(reservesNewMethod[1].token, reservesOriginalMethod[1].token);
        assertEq(reservesNewMethod[1].reserveAmount, reservesOriginalMethod[1].reserveAmount);
        _checkVariance(reservesOriginalMethod[1].rawSpotPrice, reservesNewMethod[1].rawSpotPrice);
        assertEq(reservesNewMethod[1].actualQuoteToken, reservesOriginalMethod[1].actualQuoteToken);
    }
}
