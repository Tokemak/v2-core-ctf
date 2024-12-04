// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { SYSTEM_REGISTRY_MAINNET, TREASURY, WETH_MAINNET } from "test/utils/Addresses.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

import { BaseClaimingDestinationVaultExtension } from
    "src/vault/extensions/base/BaseClaimingDestinationVaultExtension.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

//solhint-disable const-name-snakecase,func-name-mixedcase

contract BaseClaimingDestinationVaultExtensionTest is Test {
    IDestinationVault public constant dv = IDestinationVault(0x4E12227b350E8f8fEEc41A58D36cE2fB2e2d4575);
    ISystemRegistry public constant systemRegistry = ISystemRegistry(SYSTEM_REGISTRY_MAINNET);

    address public aggregator = makeAddr("AGGREGATOR");
    MockDVExtension public extension;
    MockAsyncSwapper public swapper;

    MockERC20 public mockToken1;
    MockERC20 public mockToken2;

    event ClaimingExtensionExecuted(uint256[] amountsClaimed, address[] tokensClaimed, uint256 amountAddedToRewards);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_066_621);

        mockToken1 = new MockERC20("Mock Token 1", "MT1", 18);
        mockToken2 = new MockERC20("Mock Token 2", "MT2", 18);

        // Give test contract the ability to set and execute extensions, and to set swapper on async swapper registry
        vm.startPrank(TREASURY);
        systemRegistry.accessController().setupRole(Roles.DESTINATION_VAULT_MANAGER, address(this));
        systemRegistry.accessController().setupRole(Roles.DV_REWARD_MANAGER, address(this));
        systemRegistry.accessController().setupRole(Roles.AUTO_POOL_REGISTRY_UPDATER, address(this));
        vm.stopPrank();

        // Deploy swapper, set on async swap registry
        swapper = new MockAsyncSwapper(aggregator);
        systemRegistry.asyncSwapperRegistry().register(address(swapper));

        // Deploy extension
        extension = new MockDVExtension(systemRegistry, address(swapper));

        // Add DV to whitelist for rewarder
        IBaseRewarder(dv.rewarder()).addToWhitelist(address(dv));

        // Set extension
        dv.setExtension(address(extension));

        // Warp timestamp
        vm.warp(block.timestamp + 7 days);
    }
}

contract BaseDVExtensionConstructorTest is BaseClaimingDestinationVaultExtensionTest {
    function test_RevertIf_Zero() public {
        vm.expectRevert(Errors.NotRegistered.selector);
        new MockDVExtension(systemRegistry, address(0));
    }

    function test_SetsStateCorrectly() public {
        assertEq(address(extension.asyncSwapper()), address(swapper));
        assertEq(address(extension.weth()), WETH_MAINNET);
    }
}

contract BaseDVExtensionExecuteTests is BaseClaimingDestinationVaultExtensionTest {
    function test_RevertIf_NonDVCaller() public {
        // Data doesn't matter, modifier check happens first
        bytes memory data = abi.encode("");

        // Modifier that tests this uses `address(this)` to validate DV in delegatecall context, will be address of
        // extension when calling directly.
        vm.expectRevert(Errors.NotRegistered.selector);
        extension.execute(data);
    }

    function test_RevertIf_NoSwapParams() public {
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params =
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams({
            sendToRewarder: true,
            claimData: abi.encode(""), // Check happens before this is sent to _claim
            swapParams: new SwapParams[](0)
        });
        bytes memory data = abi.encode(params);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "swapParamsLength"));
        dv.executeExtension(data);
    }

    function test_SingleTokenClaimed_Execute() public {
        // Constants
        uint256 mockToken1Claim = 1.5e18;
        uint256 wethAmountReceivedOnSwap = 0.75e18;

        // Prep data
        MockDVExtension.MockExtensionParams[] memory mockExtensionParams = new MockDVExtension.MockExtensionParams[](1);
        SwapParams[] memory swapParams = new SwapParams[](1);

        mockExtensionParams[0] = MockDVExtension.MockExtensionParams({ token: address(mockToken1), amount: 1.5e18 });

        swapParams[0] = SwapParams({
            sellTokenAddress: address(mockToken1),
            sellAmount: mockToken1Claim,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: wethAmountReceivedOnSwap,
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });

        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params =
        BaseClaimingDestinationVaultExtension
            // solhint-disable-next-line max-line-length
            .BaseClaimingExtensionParams({
            sendToRewarder: true,
            claimData: abi.encode(mockExtensionParams),
            swapParams: swapParams
        });

        bytes memory data = abi.encode(params);

        uint256[] memory amountsClaimed = new uint256[](1);
        address[] memory tokensClaimed = new address[](1);

        amountsClaimed[0] = mockToken1Claim;
        tokensClaimed[0] = address(mockToken1);

        // Snapshot some values
        uint256 wethAmountDVBefore = IERC20(WETH_MAINNET).balanceOf(address(dv));
        uint256 wethAmountRewarderBefore = IERC20(WETH_MAINNET).balanceOf(dv.rewarder());
        uint256 wethAmountAddressThisBefore = IERC20(WETH_MAINNET).balanceOf(address(this));

        // Supply dv with eth. Mock swapper is set up to deposit eth for weth
        vm.deal(address(dv), wethAmountReceivedOnSwap);

        vm.expectEmit(true, true, true, true);
        emit ClaimingExtensionExecuted(amountsClaimed, tokensClaimed, wethAmountReceivedOnSwap);
        dv.executeExtension(data);

        assertEq(mockToken1.balanceOf(address(dv)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(dv.rewarder()), wethAmountRewarderBefore + wethAmountReceivedOnSwap);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(dv)), wethAmountDVBefore);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), wethAmountAddressThisBefore);
    }

    function test_SingleTokenClaimed_SendToCaller() public {
        // Constants
        uint256 mockToken1Claim = 1.5e18;
        uint256 wethAmountReceivedOnSwap = 0.75e18;

        // Prep data
        MockDVExtension.MockExtensionParams[] memory mockExtensionParams = new MockDVExtension.MockExtensionParams[](1);
        SwapParams[] memory swapParams = new SwapParams[](1);

        mockExtensionParams[0] = MockDVExtension.MockExtensionParams({ token: address(mockToken1), amount: 1.5e18 });

        swapParams[0] = SwapParams({
            sellTokenAddress: address(mockToken1),
            sellAmount: mockToken1Claim,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: wethAmountReceivedOnSwap,
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });

        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params =
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams({
            sendToRewarder: false,
            claimData: abi.encode(mockExtensionParams),
            swapParams: swapParams
        });

        bytes memory data = abi.encode(params);

        uint256[] memory amountsClaimed = new uint256[](1);
        address[] memory tokensClaimed = new address[](1);

        amountsClaimed[0] = mockToken1Claim;
        tokensClaimed[0] = address(mockToken1);

        // Snapshot some values
        uint256 wethAmountDVBefore = IERC20(WETH_MAINNET).balanceOf(address(dv));
        uint256 wethAmountRewarderBefore = IERC20(WETH_MAINNET).balanceOf(dv.rewarder());
        uint256 wethAmountAddressThisBefore = IERC20(WETH_MAINNET).balanceOf(address(this));

        // Supply dv with eth. Mock swapper is set up to deposit eth for weth
        vm.deal(address(dv), wethAmountReceivedOnSwap);

        vm.expectEmit(true, true, true, true);
        emit ClaimingExtensionExecuted(amountsClaimed, tokensClaimed, wethAmountReceivedOnSwap);
        dv.executeExtension(data);

        assertEq(mockToken1.balanceOf(address(dv)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), wethAmountAddressThisBefore + wethAmountReceivedOnSwap);
        assertEq(IERC20(WETH_MAINNET).balanceOf(dv.rewarder()), wethAmountRewarderBefore);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(dv)), wethAmountDVBefore);
    }

    function test_MultiTokenClaim_Execute() public {
        // Constants
        uint256 mockToken1Claim = 1.5e18;
        uint256 mockToken2Claim = 2.6e18;
        uint256 wethReceivedOnSwapMockToken1 = 0.75e18;
        uint256 wethReceivedOnSwapMockToken2 = 2.5e18;

        // Prep data
        MockDVExtension.MockExtensionParams[] memory mockExtensionParams = new MockDVExtension.MockExtensionParams[](2);
        SwapParams[] memory swapParams = new SwapParams[](2);

        mockExtensionParams[0] =
            MockDVExtension.MockExtensionParams({ token: address(mockToken1), amount: mockToken1Claim });
        mockExtensionParams[1] =
            MockDVExtension.MockExtensionParams({ token: address(mockToken2), amount: mockToken2Claim });

        swapParams[0] = SwapParams({
            sellTokenAddress: address(mockToken1),
            sellAmount: mockToken1Claim,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: wethReceivedOnSwapMockToken1,
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });
        swapParams[1] = SwapParams({
            sellTokenAddress: address(mockToken2),
            sellAmount: mockToken2Claim,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: wethReceivedOnSwapMockToken2,
            data: abi.encode(""),
            extraData: abi.encode(""),
            deadline: block.timestamp
        });

        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params =
        BaseClaimingDestinationVaultExtension
            // solhint-disable-next-line max-line-length
            .BaseClaimingExtensionParams({
            sendToRewarder: true,
            claimData: abi.encode(mockExtensionParams),
            swapParams: swapParams
        });

        bytes memory data = abi.encode(params);

        uint256[] memory amountsClaimed = new uint256[](2);
        address[] memory tokensClaimed = new address[](2);

        amountsClaimed[0] = mockToken1Claim;
        amountsClaimed[1] = mockToken2Claim;
        tokensClaimed[0] = address(mockToken1);
        tokensClaimed[1] = address(mockToken2);

        // Snapshot values
        uint256 wethAmountDVBefore = IERC20(WETH_MAINNET).balanceOf(address(dv));
        uint256 wethAmountRewarderBefore = IERC20(WETH_MAINNET).balanceOf(dv.rewarder());
        uint256 wethAmountAddressThisBefore = IERC20(WETH_MAINNET).balanceOf(address(this));

        // Supply dv with eth.  Mock swapper is set up to deposit eth for weth
        vm.deal(address(dv), wethReceivedOnSwapMockToken1 + wethReceivedOnSwapMockToken2);

        vm.expectEmit(true, true, true, true);
        emit ClaimingExtensionExecuted(
            amountsClaimed, tokensClaimed, wethReceivedOnSwapMockToken1 + wethReceivedOnSwapMockToken2
        );
        dv.executeExtension(data);

        assertEq(mockToken1.balanceOf(address(dv)), 0);
        assertEq(mockToken2.balanceOf(address(dv)), 0);
        assertEq(
            IERC20(WETH_MAINNET).balanceOf(dv.rewarder()),
            wethAmountRewarderBefore + wethReceivedOnSwapMockToken1 + wethReceivedOnSwapMockToken2
        );
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(dv)), wethAmountDVBefore);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(this)), wethAmountAddressThisBefore);
    }
}

contract MockDVExtension is BaseClaimingDestinationVaultExtension {
    struct MockExtensionParams {
        address token;
        uint256 amount;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _asyncSwapper
    ) BaseClaimingDestinationVaultExtension(_systemRegistry, _asyncSwapper) { }

    function _claim(
        bytes memory data
    ) internal override returns (uint256[] memory amountsClaimed, address[] memory tokensClaimed) {
        MockExtensionParams[] memory params = abi.decode(data, (MockExtensionParams[]));

        amountsClaimed = new uint256[](params.length);
        tokensClaimed = new address[](params.length);

        for (uint256 i = 0; i < params.length; ++i) {
            MockERC20(params[i].token).mint(address(this), params[i].amount);
            amountsClaimed[i] = params[i].amount;
            tokensClaimed[i] = params[i].token;
        }
    }
}

contract MockAsyncSwapper is IAsyncSwapper {
    // Just using this as a place to send sell tokens
    address public immutable AGGREGATOR;

    constructor(
        address _aggregator
    ) {
        AGGREGATOR = _aggregator;
    }

    function swap(
        SwapParams memory swapParams
    ) public override returns (uint256 buyTokenAmountReceived) {
        address sellToken = swapParams.sellTokenAddress;
        uint256 sellAmount = swapParams.sellAmount;
        uint256 buyAmount = swapParams.buyAmount;

        // Because this is in delegatecall context, can just transfer out.
        IERC20(sellToken).transfer(AGGREGATOR, sellAmount);

        IWETH9 weth = IWETH9(WETH_MAINNET);
        weth.deposit{ value: buyAmount }();

        buyTokenAmountReceived = buyAmount;
    }
}
