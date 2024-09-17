// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count,func-name-mixedcase,avoid-low-level-calls

import { Test } from "forge-std/Test.sol";

import {
    TOKE_MAINNET,
    WETH_MAINNET,
    AURA_MAINNET,
    BAL_VAULT,
    CVX_MAINNET,
    CONVEX_BOOSTER,
    AURA_BOOSTER,
    OETH_MAINNET,
    RETH_MAINNET,
    CURVE_META_REGISTRY_MAINNET,
    RPL_MAINNET
} from "test/utils/Addresses.sol";

import { Roles } from "src/libs/Roles.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SystemRegistry } from "src/SystemRegistry.sol";
import { SystemSecurityL1 } from "src/security/SystemSecurityL1.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IncentivePricingStats } from "src/stats/calculators/IncentivePricingStats.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { BalancerAuraDestinationVault } from "src/vault/BalancerAuraDestinationVault.sol";
import { CurveConvexDestinationVault } from "src/vault/CurveConvexDestinationVault.sol";
import { CurveResolverMainnet, ICurveMetaRegistry } from "src/utils/CurveResolverMainnet.sol";
import { DestinationIncentiveChecker } from "src/utils/DestinationIncentiveChecker.sol";

contract DestinationIncentiveCheckerTest is Test {
    string public constant BALANCER_AURA_DEST = "BalancerAuraDestination";
    string public constant CURVE_CONVEX_DEST = "CurveConvexDestination";

    address public constant BAL_RETH_WETH = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    address public constant CURVE_OETH_WETH = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;

    address public constant BAL_AURA_RETH_WETH_REWARDER = 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D;
    address public constant CURVE_CONVEX_OETH_WETH_REWARDER = 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A;

    SystemRegistry public systemRegistry;
    AccessController public accessController;
    SystemSecurityL1 public systemSecurity;
    CurveResolverMainnet public curveResolver;
    IncentivePricingStats public incentivePricingStats;
    address public curveConvexTemplate;
    address public balancerAuraTemplate;
    DestinationRegistry public destinationRegistry;
    DestinationVaultRegistry public destinationVaultRegistry;
    DestinationVaultFactory public destinationVaultFactory;
    CurveConvexDestinationVault public curveConvexDV;
    BalancerAuraDestinationVault public balancerAuraDV;
    DestinationIncentiveChecker public checker;

    address public mockCurveCalc;
    address public mockBalCalc;
    address public mockOracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_763_926);

        mockCurveCalc = makeAddr("mockCurve");
        mockBalCalc = makeAddr("mockBal");
        mockOracle = makeAddr("mockOracle");

        // System registry set up
        systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        systemRegistry.addRewardToken(WETH_MAINNET);

        // Set oracle
        vm.mockCall(mockOracle, abi.encodeWithSignature("getSystemRegistry()"), abi.encode(address(systemRegistry)));
        systemRegistry.setRootPriceOracle(mockOracle);

        // Access control set up
        accessController = new AccessController(address(systemRegistry));
        systemRegistry.setAccessController(address(accessController));
        accessController.setupRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));
        accessController.setupRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));
        accessController.setupRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, address(this));

        // System security setup
        systemSecurity = new SystemSecurityL1(systemRegistry);
        systemRegistry.setSystemSecurity(address(systemSecurity));

        // Set up Curve resolver
        curveResolver = new CurveResolverMainnet(ICurveMetaRegistry(CURVE_META_REGISTRY_MAINNET));
        systemRegistry.setCurveResolver(address(curveResolver));

        // Incentive stats set up
        incentivePricingStats = new IncentivePricingStats(systemRegistry);
        systemRegistry.setIncentivePricingStats(address(incentivePricingStats));
        _mockOracle();
        incentivePricingStats.setRegisteredToken(CVX_MAINNET);
        incentivePricingStats.setRegisteredToken(AURA_MAINNET);
        incentivePricingStats.setRegisteredToken(RPL_MAINNET);

        // Destination template set up
        curveConvexTemplate = address(new CurveConvexDestinationVault(systemRegistry, CVX_MAINNET, CONVEX_BOOSTER));
        balancerAuraTemplate = address(new BalancerAuraDestinationVault(systemRegistry, BAL_VAULT, AURA_MAINNET));

        // Destination Registry set up
        destinationRegistry = new DestinationRegistry(systemRegistry);
        systemRegistry.setDestinationTemplateRegistry(address(destinationRegistry));

        bytes32[] memory templateKeys = new bytes32[](2);
        templateKeys[0] = keccak256(abi.encode(BALANCER_AURA_DEST));
        templateKeys[1] = keccak256(abi.encode(CURVE_CONVEX_DEST));
        address[] memory templates = new address[](2);
        templates[0] = balancerAuraTemplate;
        templates[1] = curveConvexTemplate;

        destinationRegistry.addToWhitelist(templateKeys);
        destinationRegistry.register(templateKeys, templates);

        // Destination vault registry set up
        destinationVaultRegistry = new DestinationVaultRegistry(systemRegistry);
        systemRegistry.setDestinationVaultRegistry(address(destinationVaultRegistry));

        // Destination vault facotry set up
        destinationVaultFactory = new DestinationVaultFactory(systemRegistry, 100, 100);
        destinationVaultRegistry.setVaultFactory(address(destinationVaultFactory));

        //
        // Create destinations
        //

        // Curve
        address[] memory additionalTrackedTokens = new address[](1);
        additionalTrackedTokens[0] = OETH_MAINNET;
        CurveConvexDestinationVault.InitParams memory initCurve = CurveConvexDestinationVault.InitParams({
            curvePool: CURVE_OETH_WETH,
            convexStaking: CURVE_CONVEX_OETH_WETH_REWARDER,
            convexPoolId: 174
        });
        _mockCalculatorLpAndPool(mockCurveCalc, CURVE_OETH_WETH);
        curveConvexDV = CurveConvexDestinationVault(
            payable(
                destinationVaultFactory.create(
                    CURVE_CONVEX_DEST,
                    WETH_MAINNET,
                    CURVE_OETH_WETH,
                    mockCurveCalc,
                    additionalTrackedTokens,
                    keccak256("abc"),
                    abi.encode(initCurve)
                )
            )
        );

        // Bal
        additionalTrackedTokens[0] = RETH_MAINNET;
        BalancerAuraDestinationVault.InitParams memory initBal = BalancerAuraDestinationVault.InitParams({
            balancerPool: BAL_RETH_WETH,
            auraStaking: BAL_AURA_RETH_WETH_REWARDER,
            auraBooster: AURA_BOOSTER,
            auraPoolId: 109
        });
        _mockCalculatorLpAndPool(mockBalCalc, BAL_RETH_WETH);
        balancerAuraDV = BalancerAuraDestinationVault(
            destinationVaultFactory.create(
                BALANCER_AURA_DEST,
                WETH_MAINNET,
                BAL_RETH_WETH,
                mockBalCalc,
                additionalTrackedTokens,
                keccak256("bcd"),
                abi.encode(initBal)
            )
        );

        // Incentive checker set up
        checker = new DestinationIncentiveChecker(systemRegistry);
    }

    function test_ReturnsUnregisteredTokenAddress() public {
        address balAuraRewardManager = 0xBC8d9cAf4B6bf34773976c5707ad1F2778332DcA;

        // Create rewarder, stash, base token, etc for Bal
        address baseToken = makeAddr("baseToken");
        MockStashTokenBalAura stash = new MockStashTokenBalAura(baseToken, true);
        MockExtraRewarderBalAura rewarder = new MockExtraRewarderBalAura(address(stash));

        // Prank reward Manager for Bal contract, add extra rewarder to rewards
        vm.prank(balAuraRewardManager);
        BAL_AURA_RETH_WETH_REWARDER.call(abi.encodeWithSignature("addExtraReward(address)", address(rewarder)));

        // Call check, make sure we are getting desired values
        address[] memory values = checker.check();
        assertEq(values.length, 1);
        assertEq(values[0], baseToken);
    }

    function _mockCalculatorLpAndPool(address calculator, address lpAndPool) internal {
        vm.mockCall(calculator, abi.encodeWithSignature("lpToken()"), abi.encode(lpAndPool));

        vm.mockCall(calculator, abi.encodeWithSignature("pool()"), abi.encode(lpAndPool));
    }

    function _mockOracle() internal {
        vm.mockCall(mockOracle, abi.encodeWithSignature("getPriceInEth(address)"), abi.encode(1));
    }
}

contract MockExtraRewarderBalAura {
    IERC20 public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }
}

contract MockStashTokenBalAura {
    address public baseToken;
    bool public isValid;

    constructor(address _baseToken, bool _isValid) {
        baseToken = _baseToken;
        isValid = _isValid;
    }
}
