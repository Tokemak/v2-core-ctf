// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.17;

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test } from "forge-std/Test.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { IAutopoolRegistry } from "src/interfaces/vault/IAutopoolRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { Roles } from "src/libs/Roles.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { SwapRouter } from "src/swapper/SwapRouter.sol";
import { BalancerDestinationVault } from "src/vault/BalancerDestinationVault.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IRecoveryMode } from "src/interfaces/external/balancer/IRecoveryMode.sol";
import { BalancerV2Swap } from "src/swapper/adapters/BalancerV2Swap.sol";
import {
    WETH_MAINNET,
    WSETH_RETH_SFRXETH_BAL_POOL,
    BAL_VAULT,
    WSTETH_MAINNET,
    WSETH_WETH_BAL_POOL,
    BAL_WSTETH_SFRX_ETH_RETH_WHALE,
    SFRXETH_MAINNET,
    RETH_WETH_BAL_POOL,
    RETH_MAINNET,
    BALANCER_MAINNET_AUTHORIZER
} from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract BalancerDestinationVaultComposableTests is Test {
    address private constant LP_TOKEN_WHALE = BAL_WSTETH_SFRX_ETH_RETH_WHALE;

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
    BalancerDestinationVault private _destVault;

    SwapRouter private swapRouter;
    BalancerV2Swap private balSwapper;

    address[] private additionalTrackedTokens;

    function setUp() public {
        _mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_693_095);
        vm.selectFork(_mainnetFork);

        additionalTrackedTokens = new address[](0);

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
        ISwapRouter.SwapData memory wstEthWethSwapData = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: WSETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080) // wstETH/WETH pool
         });
        wstethSwapRoute[0] = wstEthWethSwapData;
        swapRouter.setSwapRoute(WSTETH_MAINNET, wstethSwapRoute);

        // setup input for Bal SFRXETH -> WETH
        ISwapRouter.SwapData[] memory sfrxEthSwapRoute = new ISwapRouter.SwapData[](2);
        sfrxEthSwapRoute[0] = ISwapRouter.SwapData({
            token: WSTETH_MAINNET,
            pool: WSETH_RETH_SFRXETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x5aee1e99fe86960377de9f88689616916d5dcabe000000000000000000000467)
        });
        sfrxEthSwapRoute[1] = wstEthWethSwapData;
        swapRouter.setSwapRoute(SFRXETH_MAINNET, sfrxEthSwapRoute);

        // setup input for Bal RETH -> WETH
        ISwapRouter.SwapData[] memory rEthSwapRoute = new ISwapRouter.SwapData[](1);
        rEthSwapRoute[0] = ISwapRouter.SwapData({
            token: address(_systemRegistry.weth()),
            pool: RETH_WETH_BAL_POOL,
            swapper: balSwapper,
            data: abi.encode(0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112)
        });
        swapRouter.setSwapRoute(RETH_MAINNET, rEthSwapRoute);

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

        _underlyer = IERC20(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.label(address(_underlyer), "underlyer");

        BalancerDestinationVault dvTemplate = new BalancerDestinationVault(_systemRegistry, BAL_VAULT);
        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        _destinationTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(dvTemplate);
        _destinationTemplateRegistry.register(dvTypes, dvAddresses);

        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: WSETH_RETH_SFRXETH_BAL_POOL });
        bytes memory initParamBytes = abi.encode(initParams);
        _testIncentiveCalculator = new TestIncentiveCalculator();
        _testIncentiveCalculator.setPoolAddress(address(_underlyer));
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

        _destVault = BalancerDestinationVault(newVault);

        _rootPriceOracle = IRootPriceOracle(vm.addr(34_399));
        vm.label(address(_rootPriceOracle), "rootPriceOracle");

        _mockSystemBound(address(_systemRegistry), address(_rootPriceOracle));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        // Set autoPool registry for permissions
        _autoPoolRegistry = IAutopoolRegistry(vm.addr(237_894));
        vm.label(address(_autoPoolRegistry), "autoPoolRegistry");
        _mockSystemBound(address(_systemRegistry), address(_autoPoolRegistry));
        _systemRegistry.setAutopoolRegistry(address(_autoPoolRegistry));

        // Disable Pool RecoveryMode
        // Note: at the forked block pool is in RecoveryMode, we want to use pool without it
        // but withdrawals from the RecoveryMode tested specifically in
        // `withdrawBaseAsset_IsPossibleWhenPoolIsInRecoveryMode` scenario.
        IRecoveryMode pool = IRecoveryMode(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.prank(BALANCER_MAINNET_AUTHORIZER);
        pool.disableRecoveryMode();
        assertFalse(pool.inRecoveryMode());
    }

    function test_initializer_ConfiguresVault() public {
        BalancerDestinationVault.InitParams memory initParams =
            BalancerDestinationVault.InitParams({ balancerPool: WSETH_RETH_SFRXETH_BAL_POOL });
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

    /// @dev Balancer pools do not deal in ETH
    function test_poolDealInEth_ReturnsFalse() public {
        assertFalse(_destVault.poolDealInEth());
    }

    function test_isComposable_TrueForComposableValues() public {
        assertTrue(_destVault.isComposable());
    }

    function test_poolType_Returns() public {
        assertEq(_destVault.poolType(), "balCompStable");
    }

    function test_exchangeName_Returns() public {
        assertEq(_destVault.exchangeName(), "balancer");
    }

    function test_underlyingTotalSupply_ReturnsCorrectValue() public {
        assertEq(_destVault.underlyingTotalSupply(), 23_955_542_978_639_386_953_281);
    }

    function test_underlyingTokens_ReturnsForComposable() public {
        address[] memory tokens = _destVault.underlyingTokens();

        assertEq(tokens.length, 3);
        assertEq(IERC20(tokens[0]).symbol(), "wstETH");
        assertEq(IERC20(tokens[1]).symbol(), "sfrxETH");
        assertEq(IERC20(tokens[2]).symbol(), "rETH");
    }

    function test_underlyingReserves() public {
        (address[] memory tokens, uint256[] memory reserves) = _destVault.underlyingReserves();
        assertEq(tokens.length, 4);
        assertEq(reserves.length, 4);

        assertEq(tokens[0], WSETH_RETH_SFRXETH_BAL_POOL);
        assertEq(tokens[1], WSTETH_MAINNET);
        assertEq(tokens[2], SFRXETH_MAINNET);
        assertEq(tokens[3], RETH_MAINNET);

        assertEq(reserves[0], 2_596_148_429_266_020_000_200_336_668_982_202);
        assertEq(reserves[1], 7_170_154_258_867_111_363_607);
        assertEq(reserves[2], 9_744_097_503_991_333_858_109);
        assertEq(reserves[3], 5_525_635_239_701_618_321_526);
    }

    function test_depositUnderlying_TokensStayInVault() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to destination vault
        assertEq(_destVault.internalDebtBalance(), 10e18);
    }

    function test_withdrawUnderlying_PullsFromVault() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        // Ensure the funds went to vault
        assertEq(_destVault.internalDebtBalance(), 10e18);

        address receiver = vm.addr(555);
        uint256 received = _destVault.withdrawUnderlying(10e18, receiver);

        assertEq(received, 10e18);
        assertEq(_underlyer.balanceOf(receiver), 10e18);
        assertEq(_destVault.externalDebtBalance(), 0e18);
        assertEq(_destVault.internalDebtBalance(), 0e18);
    }

    function test_withdrawBaseAsset_ReturnsAppropriateAmount() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        (uint256 received,,) = _destVault.withdrawBaseAsset(10e18, receiver);

        // Bal pool has a rough pool value of $48,618,767
        // Total Supply of 24059.127967424958374618
        // Eth Price: $1977.44
        // PPS: 1.01 w/10 shares ~= 10
        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_128_444_161_444_807_958);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    function test_withdrawBaseAsset_IsPossibleWhenPoolIsInRecoveryMode() public {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 10e18);

        // Give us deposit rights
        _mockIsVault(address(this), true);

        // Deposit
        _underlyer.approve(address(_destVault), 10e18);
        _destVault.depositUnderlying(10e18);

        address receiver = vm.addr(555);
        uint256 startingBalance = _asset.balanceOf(receiver);

        // Put pool into RecoveryMode
        IRecoveryMode pool = IRecoveryMode(WSETH_RETH_SFRXETH_BAL_POOL);
        vm.prank(BALANCER_MAINNET_AUTHORIZER);
        pool.enableRecoveryMode();
        assertTrue(pool.inRecoveryMode());

        // Run withdrawal
        (uint256 received,,) = _destVault.withdrawBaseAsset(10e18, receiver);

        // Bal pool has a rough pool value of $48,618,767
        // Total Supply of 24059.127967424958374618
        // Eth Price: $1977.44
        // PPS: 1.01 w/10 shares ~= 10
        assertEq(_asset.balanceOf(receiver) - startingBalance, 10_128_444_161_444_807_958);
        assertEq(received, _asset.balanceOf(receiver) - startingBalance);
    }

    //
    // Below tests test functionality introduced in response to Sherlock 625.
    // Link here: https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/invalid/625.md
    //
    function test_ExternalDebtBalance_UpdatesProperly_DepositAndWithdrawal() external {
        uint256 localDepositAmount = 1000;
        uint256 localWithdrawalAmount = 600;

        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), localDepositAmount);

        // Allow this address to deposit.
        _mockIsVault(address(this), true);

        // Check balances before deposit.
        assertEq(_destVault.externalDebtBalance(), 0);
        assertEq(_destVault.internalDebtBalance(), 0);

        // Approve and deposit.
        _underlyer.approve(address(_destVault), localDepositAmount);
        _destVault.depositUnderlying(localDepositAmount);

        // Check balances after deposit.
        assertEq(_destVault.internalDebtBalance(), localDepositAmount);
        assertEq(_destVault.externalDebtBalance(), 0);

        _destVault.withdrawUnderlying(localWithdrawalAmount, address(this));

        // Check balances after withdrawing underlyer.
        assertEq(_destVault.internalDebtBalance(), localDepositAmount - localWithdrawalAmount);
        assertEq(_destVault.externalDebtBalance(), 0);
    }

    function test_InternalDebtBalance_CannotBeManipulated() external {
        // Get some tokens to play with
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        // Make sure balance of underlyer is on DV.
        assertEq(_underlyer.balanceOf(address(_destVault)), 1000);

        // Check to make sure `internalDebtBalance()` not changed. Used to be queried with `balanceOf(_destVault)`.
        assertEq(_destVault.internalDebtBalance(), 0);
    }

    function test_InternalQueriedBalance_CapturesUnderlyerInVault() external {
        // Transfer tokens to address.
        vm.prank(LP_TOKEN_WHALE);
        _underlyer.transfer(address(this), 1000);

        // Transfer to DV directly.
        _underlyer.transfer(address(_destVault), 1000);

        assertEq(_destVault.internalQueriedBalance(), 1000);
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
