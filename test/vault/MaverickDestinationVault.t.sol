// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase,max-stats-count

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault, IDestinationVault } from "src/vault/DestinationVault.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import {
    WETH_MAINNET,
    MAV_WSTETH_WETH_POOL,
    MAV_ROUTER,
    MAV_WSTETH_WETH_BOOSTED_POS_REWARDER,
    MAV_WSTETH_WETH_BOOSTED_POS,
    BAL_VAULT,
    LDO_MAINNET,
    WSTETH_MAINNET,
    WSETH_WETH_BAL_POOL
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";
import { MaverickDestinationVault } from "src/vault/MaverickDestinationVault.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";

contract MaverickDestinationVaultTests is Test {
    uint256 private _mainnetFork;

    SystemRegistry private _systemRegistry;
    AccessController private _accessController;
    DestinationVaultFactory private _destinationVaultFactory;
    DestinationVaultRegistry private _destinationVaultRegistry;
    DestinationRegistry private _destinationTemplateRegistry;

    IAutopoolRegistry private _autoPoolRegistry;
    IRootPriceOracle private _rootPriceOracle;

    IWETH9 private _asset;

    IERC20 private _underlyer;
    TestIncentiveCalculator private _testIncentiveCalculator;
    MaverickDestinationVault private _destVault;

    SwapRouter private swapRouter;
    BalancerV2Swap private balSwapper;

    address[] private additionalTrackedTokens;

    function setUp() public {
        additionalTrackedTokens = new address[](0);

        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_360_127);
        vm.selectFork(_mainnetFork);

        vm.label(address(this), "testContract");

        _systemRegistry = new SystemRegistry(vm.addr(100), WETH_MAINNET);

        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));

        _asset = IWETH9(WETH_MAINNET);

        _systemRegistry.addRewardToken(WETH_MAINNET);

        // Setup swap router

        swapRouter = new SwapRouter(_systemRegistry);
        balSwapper = new BalancerV2Swap(address(swapRouter), BAL_VAULT);
        // setup input for Bal WSTETH -> WETH
        ISwapRouter.SwapData[] memory wstethSwapRoute = new ISwapRouter.SwapData[](1);
        wstethSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: WSETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080) // wstETH/WETH pool
         });
        _accessController.grantRole(Roles.SWAP_ROUTER_MANAGER, address(this));
        swapRouter.setSwapRoute(WSTETH_MAINNET, wstethSwapRoute);
        _systemRegistry.setSwapRouter(address(swapRouter));
        vm.label(address(swapRouter), "swapRouter");
        vm.label(address(balSwapper), "balSwapper");

        _accessController.grantRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, address(this));
        _accessController.grantRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER, address(this));

        // Setup the Destination system
        _destinationVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _destinationTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(_destinationTemplateRegistry));
        _systemRegistry.setDestinationVaultRegistry(address(_destinationVaultRegistry));
        _destinationVaultFactory = new DestinationVaultFactory(_systemRegistry, 1, 1000);
        _destinationVaultRegistry.setVaultFactory(address(_destinationVaultFactory));

        _underlyer = IERC20(MAV_WSTETH_WETH_BOOSTED_POS);
        vm.label(address(_underlyer), "underlyer");

        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(MAV_WSTETH_WETH_POOL));

        MaverickDestinationVault dvTemplate = new MaverickDestinationVault(_systemRegistry);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        MaverickDestinationVault.InitParams memory initParams = MaverickDestinationVault.InitParams({
            maverickRouter: MAV_ROUTER,
            maverickBoostedPosition: MAV_WSTETH_WETH_BOOSTED_POS,
            maverickRewarder: MAV_WSTETH_WETH_BOOSTED_POS_REWARDER,
            maverickPool: MAV_WSTETH_WETH_POOL
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt1"),
                initParamBytes
            )
        );
        vm.label(newVault, "destVault");

        _destVault = MaverickDestinationVault(newVault);

        _rootPriceOracle = IRootPriceOracle(vm.addr(34_399));
        vm.label(address(_rootPriceOracle), "rootPriceOracle");

        _mockSystemBound(address(_systemRegistry), address(_rootPriceOracle));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));
        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));
    }

    function test_initializer_ConfiguresVault() public {
        MaverickDestinationVault.InitParams memory initParams = MaverickDestinationVault.InitParams({
            maverickRouter: MAV_ROUTER,
            maverickBoostedPosition: MAV_WSTETH_WETH_BOOSTED_POS,
            maverickRewarder: MAV_WSTETH_WETH_BOOSTED_POS_REWARDER,
            maverickPool: MAV_WSTETH_WETH_POOL
        });
        bytes memory initParamBytes = abi.encode(initParams);

        address payable newVault = payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );

        assertTrue(DestinationVault(newVault).underlyingTokens().length > 0);
    }

    function test_exchangeName_ReturnsMaverick() public {
        assertEq(_destVault.exchangeName(), "maverick");
    }

    function test_poolType_ReturnsMaverick() public {
        assertEq(_destVault.poolType(), "maverick");
    }

    function test_underlyingTotalSupply_ReturnsCorrectValue() public {
        assertEq(_destVault.underlyingTotalSupply(), 20_075_609_907_047_742_150);
    }

    // @dev Maverick destination vaults do not handle pool with ETH yet
    function test_poolDealInEth_ReturnsFalse() public {
        assertFalse(_destVault.poolDealInEth());
    }

    function test_underlyingTokens_ReturnsPoolTokens() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 2);
        assertEq(IERC20(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20(tokens[1]).symbol(), "WETH");
    }

    function test_underlyingReserves() public {
        (address[] memory tokens, uint256[] memory reserves) = _destVault.underlyingReserves();
        assertEq(tokens.length, 2);
        assertEq(reserves.length, 2);

        assertEq(tokens[0], WSTETH_MAINNET);
        assertEq(tokens[1], WETH_MAINNET);

        assertEq(reserves[0], 0);
        assertEq(reserves[1], 25_604_127_757_393_910_704);
    }

    function test_deposit_IsStakedIntoRewarder() public {
        // Get some tokens to play with
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 100e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        // Ensure the funds went to Mav
        assertEq(_destVault.externalQueriedBalance(), 100e18);
    }

    function test_collectRewards_TransfersToCaller() public {
        // Get some tokens to play with
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 100e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        // Move 7 days later
        vm.roll(block.number + 7200 * 7);
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 7 days);

        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(this));

        IERC20 ldo = IERC20(LDO_MAINNET);

        uint256 preBalLDO = ldo.balanceOf(address(this));

        (uint256[] memory amounts, address[] memory tokens) = _destVault.collectRewards();

        assertEq(amounts.length, tokens.length);
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0]), address(0));
        assertEq(address(tokens[1]), LDO_MAINNET);

        assertTrue(amounts[0] == 0);
        assertTrue(amounts[1] > 0);

        uint256 afterBalLDO = ldo.balanceOf(address(this));

        assertEq(amounts[1], afterBalLDO - preBalLDO);
    }

    function test_withdrawUnderlying_SendsOneForOneToReceiver() public {
        // Get some tokens to play with
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 100e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 100e18);
        _destVault.depositUnderlying(100e18);

        // Ensure the funds went to Mav
        assertEq(_destVault.externalQueriedBalance(), 100e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(50e18, receiver);

        assertEq(received, 50e18);
        assertEq(_underlyer.balanceOf(receiver), 50e18);
    }

    function test_withdrawBaseAsset_SwapsToBaseAndSendsToReceiver() public {
        // Get some tokens to play with
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 1e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 1e18);
        _destVault.depositUnderlying(1e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        (uint256 received,,) = _destVault.withdrawBaseAsset(5e17, receiver);

        assertEq(_asset.balanceOf(receiver) - startingBalance, 637_692_400_777_456_012);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    //
    // Below tests test functionality introduced in response to Sherlock 625.
    // Link here: https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/invalid/625.md
    //
    function test_ExternalDebtBalance_UpdatesProperly_DepositAndWithdrawal() external {
        uint256 localDepositAmount = 1000;
        uint256 localWithdrawalAmount = 600;

        // Deal this address some tokens.
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), localDepositAmount);

        // Allow this address to deposit.
        _mockIsVault(address(this), true);

        // Check balances before deposit.
        assertEq(_destVault.externalDebtBalance(), 0);
        assertEq(_destVault.internalDebtBalance(), 0);

        // Approve and deposit.
        _underlyer.approve(address(_destVault), localDepositAmount);
        _destVault.depositUnderlying(localDepositAmount);

        // Check balances after deposit.
        assertEq(_destVault.internalDebtBalance(), 0);
        assertEq(_destVault.externalDebtBalance(), localDepositAmount);

        _destVault.withdrawUnderlying(localWithdrawalAmount, address(this));

        // Check balances after withdrawing underlyer.
        assertEq(_destVault.internalDebtBalance(), 0);
        assertEq(_destVault.externalDebtBalance(), localDepositAmount - localWithdrawalAmount);
    }

    function test_InternalDebtBalance_CannotBeManipulated() external {
        // Deal this address some underlyer.
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        // Make sure balance of underlyer is on DV.
        assertEq(_underlyer.balanceOf(address(_destVault)), 1000);

        // Check to make sure `internalDebtBalance()` not changed. Used to be queried with `balanceOf(_destVault)`.
        assertEq(_destVault.internalDebtBalance(), 0);
    }

    function test_ExternalDebtBalance_CannotBeManipulated() external {
        // Deal this address some underlyer.
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 1000);

        IReward rewarder = IReward(MAV_WSTETH_WETH_BOOSTED_POS_REWARDER);

        // Stake on behalf of DV into Mav rewarder.
        _underlyer.approve(address(rewarder), 1000);
        rewarder.stake(1000, address(_destVault));

        // Ensure that rewarder has balance for DV.
        assertEq(rewarder.balanceOf(address(_destVault)), 1000);

        // Make sure that DV not picking up external balances.
        assertEq(_destVault.externalDebtBalance(), 0);
    }

    function test_InternalQueriedBalance_CapturesUnderlyerInVault() external {
        // Deal token to this contract.
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        assertEq(_destVault.internalQueriedBalance(), 1000);
    }

    function test_ExternalQueriedBalance_CapturesUnderlyerNotStakedByVault() external {
        // Deal this address some underlyer.
        deal(address(MAV_WSTETH_WETH_BOOSTED_POS), address(this), 1000);

        IReward rewarder = IReward(MAV_WSTETH_WETH_BOOSTED_POS_REWARDER);

        // Stake on behalf of DV into Mav rewarder.
        _underlyer.approve(address(rewarder), 1000);
        rewarder.stake(1000, address(_destVault));

        // Ensure that rewarder has balance for DV.
        assertEq(rewarder.balanceOf(address(_destVault)), 1000);

        // Make sure that DV not picking up external balances.  Used to query rewarder.
        assertEq(_destVault.externalQueriedBalance(), 1000);
    }

    function test_DestinationVault_getPool() external {
        assertEq(_destVault.getPool(), MAV_WSTETH_WETH_POOL);
        assertEq(IDestinationVault(_destVault).getPool(), MAV_WSTETH_WETH_POOL);
    }

    function test_validateCalculator_EnsuresMatchingUnderlyingWithCalculator() external {
        MaverickDestinationVault.InitParams memory initParams = MaverickDestinationVault.InitParams({
            maverickRouter: MAV_ROUTER,
            maverickBoostedPosition: MAV_WSTETH_WETH_BOOSTED_POS,
            maverickRewarder: MAV_WSTETH_WETH_BOOSTED_POS_REWARDER,
            maverickPool: MAV_WSTETH_WETH_POOL
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(MAV_WSTETH_WETH_POOL));

        TestERC20 badUnderlyer = new TestERC20("X", "X");

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector, address(_underlyer), address(badUnderlyer), "lp"
            )
        );
        payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(badUnderlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );
    }

    function test_validateCalculator_EnsuresMatchingPoolWithCalculator() external {
        address badPool = makeAddr("badPool");

        MaverickDestinationVault.InitParams memory initParams = MaverickDestinationVault.InitParams({
            maverickRouter: MAV_ROUTER,
            maverickBoostedPosition: MAV_WSTETH_WETH_BOOSTED_POS,
            maverickRewarder: MAV_WSTETH_WETH_BOOSTED_POS_REWARDER,
            maverickPool: badPool
        });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setLpToken(address(_underlyer));
        _testIncentiveCalculator.setPoolAddress(address(MAV_WSTETH_WETH_POOL));

        vm.expectRevert(
            abi.encodeWithSelector(
                DestinationVault.InvalidIncentiveCalculator.selector,
                address(MAV_WSTETH_WETH_POOL),
                address(badPool),
                "pool"
            )
        );
        payable(
            _destinationVaultFactory.create(
                "template",
                address(_asset),
                address(_underlyer),
                address(_testIncentiveCalculator),
                additionalTrackedTokens,
                keccak256("salt2"),
                initParamBytes
            )
        );
    }

    function _mockSystemBound(address registry, address addr) internal {
        vm.mockCall(addr, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(registry));
    }

    function _mockIsVault(address vault, bool isVault) internal {
        vm.mockCall(
            address(_autoPoolRegistry),
            abi.encodeWithSelector(IAutopoolRegistry.isVault.selector, vault),
            abi.encode(isVault)
        );
    }
}
