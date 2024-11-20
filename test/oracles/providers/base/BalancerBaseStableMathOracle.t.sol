// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {
    BalancerBaseStableMathOracle,
    ISystemRegistry,
    ISpotPriceOracle
} from "src/oracles/providers/base/BalancerBaseStableMathOracle.sol";
import { Errors } from "src/utils/Errors.sol";

contract BalancerBaseStableMathOracleTest is Test {
    ISystemRegistry public registry;
    MockBalancerBaseStableMathOracle public baseOracle;

    address public token;
    address public pool;
    address public quote;
    address public lp;

    function setUp() public virtual {
        registry = ISystemRegistry(makeAddr("registry"));
        token = makeAddr("token");
        pool = makeAddr("pool");
        quote = makeAddr("quote");
        lp = pool; // Same in Bal pools

        baseOracle = new MockBalancerBaseStableMathOracle(registry);
    }
}

contract BalancerBaseStableMathOracleConstructorTest is BalancerBaseStableMathOracleTest {
    function test_StateSetOnConstruction() public {
        assertEq(address(baseOracle.getSystemRegistry()), address(registry));
    }
}

contract BalancerBaseStableMathOracleGetSpotPriceTest is BalancerBaseStableMathOracleTest {
    function test_Reverts_TokenZero_getSpotPrice() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        baseOracle.getSpotPrice(address(0), pool, quote);
    }

    function test_Reverts_PoolZero_getSpotPrice() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        baseOracle.getSpotPrice(token, address(0), quote);
    }

    function test_Reverts_QuoteZero_getSpotPrice() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "requestedQuoteToken"));
        baseOracle.getSpotPrice(token, pool, address(0));
    }

    function test_Revert_NoTokensReturned_getSpotPrice() public {
        // Only think that matters here is that tokens has zero length
        uint256 amp = 0;
        uint256 totalSupply = 0;
        uint256[] memory scalingFactors;
        uint256[] memory liveBalances;
        uint256[] memory rawBalances;
        IERC20[] memory tokens;
        baseOracle.setState(amp, totalSupply, scalingFactors, liveBalances, rawBalances, tokens);

        vm.expectRevert(abi.encodeWithSelector(BalancerBaseStableMathOracle.InvalidPool.selector, pool));
        baseOracle.getSpotPrice(token, pool, quote);
    }

    function test_Revert_TokenNotInPool_getSpotPrice() public {
        uint256 amp = 0;
        uint256 totalSupply = 0;
        uint256[] memory scalingFactors;
        uint256[] memory liveBalances;
        uint256[] memory rawBalances;
        IERC20[] memory tokens;

        address poolToken1 = makeAddr("poolToken1");
        address poolToken2 = makeAddr("poolToken2");

        // Set up tokens to return two tokens, neither of which are token being priced
        tokens = new IERC20[](2);
        tokens[0] = IERC20(poolToken1);
        tokens[1] = IERC20(poolToken2);

        baseOracle.setState(amp, totalSupply, scalingFactors, liveBalances, rawBalances, tokens);

        vm.expectRevert(abi.encodeWithSelector(BalancerBaseStableMathOracle.InvalidToken.selector, token));
        baseOracle.getSpotPrice(token, pool, quote);
    }

    function test_AdjustedWhenQuoteNotInPool_getSpotPrice() public {
        uint256 amp = 200_000;
        uint256 totalSupply = 0; // Doesn't matter for this one
        uint256[] memory scalingFactors;
        uint256[] memory liveBalances;
        uint256[] memory rawBalances;
        IERC20[] memory tokens;

        address poolToken1 = makeAddr("poolToken1");

        // Returns token and token that is not quote, will force quote to be `poolToken1`
        tokens = new IERC20[](2);
        tokens[0] = IERC20(token);
        tokens[1] = IERC20(poolToken1);

        // Setting scaling, live balances.  All 1e18, values don't matter for this
        liveBalances = new uint256[](2);
        scalingFactors = new uint256[](2);

        liveBalances[0] = 1e22;
        liveBalances[1] = 1e22;

        scalingFactors[0] = 1e18;
        scalingFactors[1] = 1e18;

        baseOracle.setState(amp, totalSupply, scalingFactors, liveBalances, rawBalances, tokens);

        // Call to token decimals in _getSpotPrice()
        vm.mockCall(token, abi.encodeWithSignature("decimals()"), abi.encode(18));

        (, address actualQuote) = baseOracle.getSpotPrice(token, pool, quote);
        assertEq(actualQuote, poolToken1);
    }
}

contract BalancerBaseStableMathOracleGetSafeSpotPriceInfoTest is BalancerBaseStableMathOracleTest {
    function test_Reverts_PoolZero_getSafeSpotPriceInfo() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "pool"));
        baseOracle.getSafeSpotPriceInfo(address(0), lp, quote);
    }

    function test_Reverts_QuoteTokenZero_getSafeSpotPriceInfo() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "quoteToken"));
        baseOracle.getSafeSpotPriceInfo(pool, lp, address(0));
    }

    function test_Reverts_DifferentPoolAndLp_getSafeSpotPriceInfo() public {
        vm.expectRevert(abi.encodeWithSelector(BalancerBaseStableMathOracle.InvalidPool.selector, pool));
        baseOracle.getSafeSpotPriceInfo(pool, address(0), quote);
    }

    function test_ReturnsCorrectData() public {
        uint256 amp = 200_000; // Based on mainnet pools
        uint256 totalSupply = 1.1e18;
        uint256[] memory scalingFactors;
        uint256[] memory liveBalances;
        uint256[] memory rawBalances;
        IERC20[] memory tokens;

        tokens = new IERC20[](2);
        tokens[0] = IERC20(token);
        tokens[1] = IERC20(quote);

        // Setting scaling, live balances.  All 1e18, values don't matter for this
        liveBalances = new uint256[](2);
        rawBalances = new uint256[](2);
        scalingFactors = new uint256[](2);

        liveBalances[0] = 1.2e22;
        liveBalances[1] = 1.5e22;

        rawBalances[0] = 1.2e22;
        rawBalances[1] = 1.5e22;

        scalingFactors[0] = 1e18;
        scalingFactors[1] = 1e18;

        baseOracle.setState(amp, totalSupply, scalingFactors, liveBalances, rawBalances, tokens);

        // token and quote decimals will be called in _getSpotPrice
        vm.mockCall(token, abi.encodeWithSignature("decimals()"), abi.encode(18));
        vm.mockCall(quote, abi.encodeWithSignature("decimals()"), abi.encode(18));

        (uint256 returnedTotalSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserveInfo) =
            baseOracle.getSafeSpotPriceInfo(pool, lp, quote);

        // Not checking exact price here, more stringent testing through integration testing
        assertEq(returnedTotalSupply, totalSupply);
        assertEq(reserveInfo[0].token, token);
        assertEq(reserveInfo[0].reserveAmount, liveBalances[0]);
        assertGt(reserveInfo[0].rawSpotPrice, 0);
        assertEq(reserveInfo[0].actualQuoteToken, quote);
        assertEq(reserveInfo[1].token, quote);
        assertEq(reserveInfo[1].reserveAmount, liveBalances[1]);
        assertGt(reserveInfo[1].rawSpotPrice, 0);
        assertEq(reserveInfo[1].actualQuoteToken, token);
    }
}

/// @dev This contract overrides functions from the base and allows us to set and return values to directly test
/// functionality that would be difficult to test in a real scenario
contract MockBalancerBaseStableMathOracle is BalancerBaseStableMathOracle {
    uint256 public amp;
    uint256 public totalSupply;
    uint256[] public scalingFactors;
    uint256[] public liveBalances;
    uint256[] public rawBalances;
    IERC20[] public tokens;

    constructor(
        ISystemRegistry _registry
    ) BalancerBaseStableMathOracle(_registry) { }

    function getDescription() external pure virtual override returns (string memory) {
        return "BalMock";
    }

    function setState(
        uint256 _amp,
        uint256 _totalSupply,
        uint256[] memory _scalingFactors,
        uint256[] memory _liveBalances,
        uint256[] memory _rawBalances,
        IERC20[] memory _tokens
    ) external {
        amp = _amp;
        totalSupply = _totalSupply;
        scalingFactors = _scalingFactors;
        liveBalances = _liveBalances;
        rawBalances = _rawBalances;
        tokens = _tokens;
    }

    function _getLiveBalancesAndScalingFactors(
        bytes memory
    ) internal view virtual override returns (uint256[] memory, uint256[] memory) {
        return (liveBalances, scalingFactors);
    }

    function _getTotalSupply(
        address
    ) internal view virtual override returns (uint256) {
        return totalSupply;
    }

    function _getPoolTokens(
        address
    ) internal view virtual override returns (IERC20[] memory, uint256[] memory, bytes memory) {
        return (tokens, rawBalances, abi.encode());
    }

    function _getAmplificationParam(
        address
    ) internal view virtual override returns (uint256) {
        return amp;
    }
}
