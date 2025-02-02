// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { AutopoolMainRewarder } from "src/rewarders/AutopoolMainRewarder.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Errors } from "src/utils/Errors.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { Test } from "forge-std/Test.sol";

// solhint-disable func-name-mixedcase,max-line-length

contract AutopoolMainRewarderTest is Test {
    address public systemRegistry;
    address public accessController;
    MockERC20 public rewardToken;
    MockERC20 public stakingToken;
    address public staker; // Address of user being staked on behalf of.
    address public router;

    uint256 public newRewardRatio = 1;
    uint256 public durationInBlock = 100;
    uint256 public stakeAmount = 1000;

    AutopoolMainRewarder public rewarder;

    function setUp() public virtual {
        systemRegistry = makeAddr("SYSTEM_REGISTRY");
        accessController = makeAddr("ACCESS_CONTROLLER");
        rewardToken = new MockERC20("X", "X", 18);
        stakingToken = new MockERC20("X", "X", 18);
        staker = makeAddr("STAKER");
        router = makeAddr("ROUTER");

        // Mock system registry calls.
        vm.mockCall(systemRegistry, abi.encodeWithSignature("accessController()"), abi.encode(accessController));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("isRewardToken(address)"), abi.encode(true));
        vm.mockCall(systemRegistry, abi.encodeWithSignature("autoPoolRouter()"), abi.encode(router));

        rewarder = new AutopoolMainRewarder(
            ISystemRegistry(systemRegistry),
            address(rewardToken),
            newRewardRatio,
            durationInBlock,
            false,
            address(stakingToken)
        );
    }
}

contract WithdrawAutopoolRewarder is AutopoolMainRewarderTest {
    uint256 public withdrawAmount = 450;

    function setUp() public override {
        super.setUp();

        // Mock AccToke and Toke calls.
        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.accToke.selector), abi.encode(makeAddr("ACC_TOKE"))
        );
        vm.mockCall(systemRegistry, abi.encodeWithSelector(ISystemRegistry.toke.selector), abi.encode(makeAddr("TOKE")));

        // Set up staker with some tokens.
        stakingToken.mint(address(this), stakeAmount);
        stakingToken.approve(address(rewarder), stakeAmount);
        rewarder.stake(staker, stakeAmount);
    }

    function test_RevertsWhenWithdrawingOverAllowance() public {
        vm.expectRevert();
        rewarder.withdraw(staker, stakeAmount + 1, false);
    }

    // Testing for revert when msg.sender != account and msg.sender is not the router.
    function test_RevertsWhenIncorrectAccount() public {
        address notRouterOrStaker = makeAddr("NOT_ROUTER_OR_STAKER");
        vm.expectRevert(Errors.AccessDenied.selector);
        vm.prank(notRouterOrStaker);
        rewarder.withdraw(staker, withdrawAmount, false);
    }

    function test_RouterCanWithdraw() public {
        vm.prank(router);
        rewarder.withdraw(staker, stakeAmount, false);

        assertEq(rewarder.balanceOf(staker), 0);
        assertEq(stakingToken.balanceOf(staker), stakeAmount);
    }

    function test_ProperBalanceUpdates_AndTransfers() public {
        uint256 userRewarderBalanceBefore = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceBefore = stakingToken.balanceOf(staker);

        assertEq(userRewarderBalanceBefore, stakeAmount);
        assertEq(userStakingTokenBalanceBefore, 0);

        vm.startPrank(staker);
        rewarder.withdraw(staker, withdrawAmount, false);

        uint256 userRewarderBalanceAfter = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceAfter = stakingToken.balanceOf(staker);

        assertEq(userRewarderBalanceAfter, userRewarderBalanceBefore - withdrawAmount);
        assertEq(userStakingTokenBalanceAfter, withdrawAmount);
    }

    function test_ProperlyClaimsRewards() public {
        rewardToken.mint(address(this), stakeAmount);
        rewardToken.approve(address(rewarder), stakeAmount);

        // Mock call to access control to bypass `onlyWhitelist` modifier on queueing rewards.
        vm.mockCall(accessController, abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
        rewarder.queueNewRewards(stakeAmount);

        // Only one staker, should claim all rewards over lock duration.
        vm.roll(block.number + durationInBlock);

        vm.prank(staker);
        rewarder.withdraw(staker, stakeAmount, true);

        assertEq(rewardToken.balanceOf(staker), stakeAmount);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(address(rewarder)), 0);
    }
}

contract StakeAutopoolRewarder is AutopoolMainRewarderTest {
    function test_RevertsWhenStakingMoreThanAvailable() external {
        vm.expectRevert();
        rewarder.stake(staker, stakeAmount + 1);
    }

    function test_RouterCanStake() public {
        stakingToken.mint(router, stakeAmount);

        vm.startPrank(router);
        stakingToken.approve(address(rewarder), stakeAmount);
        rewarder.stake(staker, stakeAmount);
        vm.stopPrank();

        assertEq(rewarder.balanceOf(staker), stakeAmount);
    }

    function test_ProperlyUpdatesBalances_AndTransfers() external {
        stakingToken.mint(staker, stakeAmount);

        uint256 userRewarderBalanceBefore = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceBefore = stakingToken.balanceOf(staker);

        assertEq(userRewarderBalanceBefore, 0);
        assertEq(userStakingTokenBalanceBefore, stakeAmount);

        vm.startPrank(staker);
        stakingToken.approve(address(rewarder), stakeAmount);
        rewarder.stake(staker, stakeAmount);
        vm.stopPrank();

        uint256 userRewardBalanceAfter = rewarder.balanceOf(staker);
        uint256 userStakingTokenBalanceAfter = stakingToken.balanceOf(staker);

        assertEq(userRewardBalanceAfter, stakeAmount);
        assertEq(userStakingTokenBalanceAfter, 0);
    }
}

contract GetRewardAutopoolRewarder is AutopoolMainRewarderTest {
    function setUp() public override {
        super.setUp();

        // Set up user staking.
        stakingToken.mint(staker, stakeAmount);
        vm.startPrank(staker);
        stakingToken.approve(address(rewarder), stakeAmount);
        rewarder.stake(staker, stakeAmount);
        vm.stopPrank();

        // Set up rewards.
        rewardToken.mint(address(this), stakeAmount);
        rewardToken.approve(address(rewarder), stakeAmount);

        // Mocks calls.
        vm.mockCall(accessController, abi.encodeWithSignature("hasRole(bytes32,address)"), abi.encode(true));
        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.accToke.selector), abi.encode(makeAddr("GP_TOKE"))
        );
        vm.mockCall(
            systemRegistry, abi.encodeWithSelector(ISystemRegistry.toke.selector), abi.encode(makeAddr("toke()"))
        );

        // Queue rewards.
        rewarder.queueNewRewards(stakeAmount);
    }

    function test_getReward_RevertsWhenNotRouterOrAccount() public {
        address notRouterOrAccount = makeAddr("NOT_ROUTER_OR_ACCOUNT");
        vm.prank(notRouterOrAccount);
        vm.expectRevert(Errors.AccessDenied.selector);
        rewarder.getReward(staker, staker, false);
    }

    function test_getReward_AllowsRouterToClaim() public {
        // Roll block so all rewards are claimable.
        vm.roll(durationInBlock + 1);

        // Prank router, get rewards.
        vm.prank(router);
        rewarder.getReward(staker, staker, false);

        // Check balances post claim.
        assertEq(rewardToken.balanceOf(staker), stakeAmount);
        assertEq(rewardToken.balanceOf(address(rewarder)), 0);
    }

    function test_getReward_AllowsAccountToClaim() public {
        // Roll block so all rewards are claimable.
        vm.roll(durationInBlock + 1);

        // Prank staker, get rewards.
        vm.prank(staker);
        rewarder.getReward(staker, staker, false);

        // Check balances post claim.
        assertEq(rewardToken.balanceOf(staker), stakeAmount);
        assertEq(rewardToken.balanceOf(address(rewarder)), 0);
    }
}
