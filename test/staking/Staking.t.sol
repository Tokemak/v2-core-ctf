// solhint-disable no-console, not-rely-on-time, func-name-mixedcase
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IAccToke } from "src/interfaces/staking/IAccToke.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { Roles } from "src/libs/Roles.sol";
import { AccToke } from "src/staking/AccToke.sol";
import { Errors } from "src/utils/Errors.sol";

contract StakingTest is BaseTest {
    uint256 private stakeAmount = 1 ether;
    uint256 private maxDuration = 1461 days;

    event Stake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Unstake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Extend(
        address indexed user,
        uint256 lockupId,
        uint256 amount,
        uint256 oldEnd,
        uint256 newEnd,
        uint256 oldPoints,
        uint256 newPoints
    );
    event RewardsAdded(uint256 amount, uint256 accRewardPerShare);
    event RewardsClaimed(address indexed user, address indexed recipient, uint256 amount);
    event AdminUnlockSet(bool newUnlockState);

    // solhint-disable-next-line var-name-mixedcase
    uint256 public TOLERANCE = 1e14; // 0.01% (1e18 being 100%)

    // Fuzzing constraints
    uint256 public constant MIN_STAKE_AMOUNT = 10_000;
    uint256 public constant MAX_STAKE_AMOUNT = 100e6 * 1e18; // default 100m toke
    uint256 public constant MAX_REWARD_ADD = 1e9 * 1e18; // default 1B eth

    function setUp() public virtual override {
        super.setUp();

        // get some initial toke
        deal(address(toke), address(this), 10 ether);

        deployAccToke();

        accessController.grantRole(Roles.ACC_TOKE_MANAGER, address(this));

        assertEq(accToke.name(), "Staked Toke");
        assertEq(accToke.symbol(), "accToke");

        // approve future spending
        toke.approve(address(accToke), toke.balanceOf(address(this)));
    }

    function testDeployAccTokeInvalidMinsStakeDuration() public {
        vm.expectRevert(IAccToke.InvalidMinStakeDuration.selector);
        new AccToke(systemRegistry, block.timestamp, 0);
        vm.expectRevert(IAccToke.InvalidMinStakeDuration.selector);
        new AccToke(systemRegistry, block.timestamp, 1 days - 1);
    }

    function testStakingCanBePaused() public {
        // make sure not paused
        assertEq(accToke.paused(), false);
        // stake
        accToke.stake(stakeAmount, ONE_YEAR);
        // pause
        accToke.pause();
        // try to stake again (should revert)
        vm.expectRevert("Pausable: paused");
        accToke.stake(stakeAmount, ONE_YEAR);
        // unpause
        accToke.unpause();
        // stake again
        accToke.stake(stakeAmount, ONE_YEAR);
    }

    function testTransfersDisabled() public {
        vm.expectRevert(IAccToke.TransfersDisabled.selector);
        accToke.transfer(address(0), 1);
        vm.expectRevert(IAccToke.TransfersDisabled.selector);
        accToke.transferFrom(address(this), address(0), 1);
    }

    function testPreviewPoints() public {
        (uint256 points, uint256 end) = accToke.previewPoints(stakeAmount, ONE_YEAR);
        assertEq(points, 1_799_999_999_999_999_984);
        assertEq(end, block.timestamp + ONE_YEAR);
    }

    function testInvalidDurationsNotAllowed() public {
        // try to stake too short
        vm.expectRevert(IAccToke.StakingDurationTooShort.selector);
        accToke.stake(stakeAmount, MIN_STAKING_DURATION - 1);
        // try to stake too long
        vm.expectRevert(IAccToke.StakingDurationTooLong.selector);
        accToke.stake(stakeAmount, maxDuration + 1);
    }

    function testSetMaxDuration() public {
        // regular stake for two years
        accToke.stake(stakeAmount, 2 * ONE_YEAR);
        // change staking duration to shorter, try staking again (should fail)
        accToke.setMaxStakeDuration(ONE_YEAR);
        vm.expectRevert();
        accToke.stake(stakeAmount, 2 * ONE_YEAR);
    }

    function testIsStakeableAmount() public {
        assertTrue(accToke.isStakeableAmount(MIN_STAKE_AMOUNT));
        assertTrue(accToke.isStakeableAmount(MAX_STAKE_AMOUNT));

        assertFalse(accToke.isStakeableAmount(MIN_STAKE_AMOUNT - 1));
        assertFalse(accToke.isStakeableAmount(MAX_STAKE_AMOUNT + 1));
    }

    function testStakingAndUnstaking(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);

        //
        // stake
        //
        stake(amount, ONE_YEAR);

        IAccToke.Lockup[] memory lockups = accToke.getLockups(address(this));
        assert(lockups.length == 1);

        uint256 lockupId = 0;
        IAccToke.Lockup memory lockup = lockups[lockupId];

        assertEq(lockup.amount, amount, "Lockup amount incorrect");
        assertEq(lockup.end, block.timestamp + ONE_YEAR);

        // voting power
        // NOTE: doing exception for comparisons since with low numbers relative tolerance is trickier
        assertApproxEqRel(accToke.balanceOf(address(this)), (amount * 18) / 10, TOLERANCE, "Voting power incorrect");

        //
        // Unstake
        //

        // make sure can't unstake too early
        vm.warp(block.timestamp + ONE_YEAR - 1);
        vm.expectRevert(IAccToke.NotUnlockableYet.selector);

        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = lockupId;
        accToke.unstake(lockupIds);
        // get to proper timestamp and unlock
        vm.warp(block.timestamp + 1);
        accToke.unstake(lockupIds);
        assertEq(accToke.balanceOf(address(this)), 0);
    }

    function testStakingAndUnstakingNotByUser(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);

        //
        // stake
        //
        stake(amount, ONE_YEAR);

        IAccToke.Lockup[] memory lockups = accToke.getLockups(address(this));
        assert(lockups.length == 1);

        uint256 lockupId = 0;
        IAccToke.Lockup memory lockup = lockups[lockupId];

        assertEq(lockup.amount, amount, "Lockup amount incorrect");
        assertEq(lockup.end, block.timestamp + ONE_YEAR);

        // voting power
        // NOTE: doing exception for comparisons since with low numbers relative tolerance is trickier
        assertApproxEqRel(accToke.balanceOf(address(this)), (amount * 18) / 10, TOLERANCE, "Voting power incorrect");

        //
        // Unstake
        //
        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = lockupId;

        // get to proper timestamp and unlock
        vm.warp(block.timestamp + ONE_YEAR);
        //Router can unstake on behalf of user but a randomUser cannot
        address user = address(this);
        address router = address(systemRegistry.autoPoolRouter());
        address randomUser = address(2);

        vm.startPrank(randomUser);
        vm.expectRevert(Errors.AccessDenied.selector);
        accToke.unstake(lockupIds, user, user);
        vm.stopPrank();
        vm.startPrank(router);

        //Cannot be unstaked for zeroAddress user
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "user"));
        accToke.unstake(lockupIds, address(0), address(0));

        //Unstake for user
        accToke.unstake(lockupIds, user, user);
        vm.stopPrank();
        assertEq(accToke.balanceOf(address(this)), 0);
    }

    function testMultipleStakingAndUnstaking(
        uint256 amount
    ) public {
        _checkFuzz(amount);
        vm.assume(amount >= 40_000);

        prepareFunds(address(this), amount);

        //
        // stake 4 different stakes
        //
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);

        IAccToke.Lockup[] memory lockups = accToke.getLockups(address(this));
        assert(lockups.length == 4);

        uint256 lockupId = 0;
        IAccToke.Lockup memory lockup = lockups[lockupId];

        assertEq(lockup.amount, amount / 4, "Lockup amount incorrect");
        assertEq(lockup.end, block.timestamp + ONE_YEAR);

        // voting power
        // NOTE: doing exception for comparisons since with low numbers relative tolerance is trickier
        assertApproxEqRel(accToke.balanceOf(address(this)), (amount * 18) / 10, TOLERANCE, "Voting power incorrect");

        //
        // Unstake 3 random positions
        //

        // make sure can't unstake too early
        vm.warp(block.timestamp + ONE_YEAR - 1);
        vm.expectRevert(IAccToke.NotUnlockableYet.selector);

        uint256[] memory lockupIds = new uint256[](3);
        lockupIds[0] = lockupId;
        lockupIds[1] = 1;
        lockupIds[2] = 3;
        accToke.unstake(lockupIds);
        // get to proper timestamp and unlock
        vm.warp(block.timestamp + 1);
        accToke.unstake(lockupIds);

        // Make sure unstaked position is still relevant
        lockupId = 2;
        lockups = accToke.getLockups(address(this));
        lockup = lockups[lockupId];
        assertEq(lockup.amount, amount / 4, "Lockup amount incorrect");

        lockup = lockups[0];
        assertEq(lockup.amount, 0, "Lockup amount incorrect");
        lockup = lockups[1];
        assertEq(lockup.amount, 0, "Lockup amount incorrect");
        lockup = lockups[3];
        assertEq(lockup.amount, 0, "Lockup amount incorrect");
    }

    function testStakingMultipleTimePeriods(
        uint256 amount
    ) public {
        _checkFuzz(amount);
        prepareFunds(address(this), amount * 2);

        // stake 1: 2 years lockup
        stake(amount, 2 * ONE_YEAR);
        // stake 2: 1 year lockup
        warpAndStake(amount, ONE_YEAR, ONE_YEAR);
        // voting power should be identical
        IAccToke.Lockup[] memory lockups = accToke.getLockups(address(this));
        assert(lockups.length == 2);
        assertEq(lockups[0].points, lockups[1].points, "Lockup points should be identical");

        // unstake first lock (try without warp first)
        vm.expectRevert(IAccToke.NotUnlockableYet.selector);
        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = 0;
        accToke.unstake(lockupIds);

        warpAndUnstake(ONE_YEAR, 0);

        IAccToke.Lockup memory lockup0 = accToke.getLockups(address(this))[0];
        assertEq(lockup0.amount, 0);
        assertEq(lockup0.points, 0);

        lockupIds[0] = 1;
        // unstake second lock
        accToke.unstake(lockupIds);
        IAccToke.Lockup memory lockup1 = accToke.getLockups(address(this))[1];
        assertEq(lockup1.amount, 0);
        assertEq(lockup1.points, 0);
        assertEq(accToke.balanceOf(address(this)), 0);
    }

    function testReceive() public {
        // ensure accToke.totalSupply() > 0 (otherwise just reverts)
        stake(stakeAmount, ONE_YEAR);

        uint256 balanceBefore = address(this).balance;
        uint256 accTokeBefore = weth.balanceOf(address(accToke));

        // send eth to accToke
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = payable(accToke).call{ value: stakeAmount }("");
        assertTrue(success);

        assertEq(address(this).balance, balanceBefore - stakeAmount);
        assertEq(weth.balanceOf(address(accToke)), accTokeBefore + stakeAmount);
    }

    function testExtend(
        uint256 amount
    ) public {
        _checkFuzz(amount);
        prepareFunds(address(this), amount);

        // original stake
        stake(amount, ONE_YEAR);
        (uint256 amountBefore,, uint256 pointsBefore) = accToke.lockups(address(this), 0);
        // extend to 2 years
        vm.expectEmit(true, false, false, false);
        emit Extend(address(this), 0, amountBefore, 0, 0, 0, 0);

        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = 0;

        uint256[] memory durations = new uint256[](1);
        durations[0] = 2 * ONE_YEAR;
        accToke.extend(lockupIds, durations);
        // verify that duration (and points) increased
        IAccToke.Lockup memory lockup = accToke.getLockups(address(this))[0];
        assertEq(lockup.amount, amountBefore);
        assertEq(lockup.end, block.timestamp + 2 * ONE_YEAR);
        assert(lockup.points > pointsBefore);
    }

    function testMultipleExtend(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        vm.assume(amount >= 40_000);
        prepareFunds(address(this), amount);

        // original stake
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);
        stake(amount / 4, ONE_YEAR);

        (uint256 amountBefore,, uint256 pointsBefore) = accToke.lockups(address(this), 0);

        vm.expectEmit(true, false, false, false);
        emit Extend(address(this), 0, amountBefore, 0, 0, 0, 0);

        //Extend lockup ID 0 to 2 years and 2 and to 3 year
        uint256[] memory lockupIds = new uint256[](2);
        lockupIds[0] = 0;
        lockupIds[1] = 2;

        uint256[] memory durations = new uint256[](2);
        durations[0] = 2 * ONE_YEAR;
        durations[1] = 3 * ONE_YEAR;
        accToke.extend(lockupIds, durations);
        // verify that duration (and points) increased
        IAccToke.Lockup memory lockup = accToke.getLockups(address(this))[0];
        assertEq(lockup.amount, amountBefore);
        assertEq(lockup.end, block.timestamp + 2 * ONE_YEAR);
        assert(lockup.points > pointsBefore);

        IAccToke.Lockup memory lockup1 = accToke.getLockups(address(this))[2];
        assertEq(lockup1.amount, amountBefore);
        assertEq(lockup1.end, block.timestamp + 3 * ONE_YEAR);
        assert(lockup1.points > pointsBefore);
    }

    function testExtendUnsafeDuration() public {
        uint256 amount = stakeAmount;
        prepareFunds(address(this), amount);

        // original stake
        stake(amount, ONE_YEAR);
        // extend past the max
        vm.expectRevert(abi.encodeWithSelector(IAccToke.StakingDurationTooLong.selector));

        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = 0;

        uint256[] memory durations = new uint256[](1);
        durations[0] = 10 * ONE_YEAR;
        accToke.extend(lockupIds, durations);
    }

    function testExtendZeroDuration() public {
        uint256 amount = stakeAmount;
        prepareFunds(address(this), amount);

        // original stake
        stake(amount, ONE_YEAR);

        // init locks
        uint256 lockupId = 0;
        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = lockupId;

        // unstake
        warpAndUnstake(ONE_YEAR, lockupId);

        // verify that lockup is zero
        IAccToke.Lockup memory lockup0 = accToke.getLockups(address(this))[lockupId];
        assertEq(lockup0.end, 0); // <- Ref: https://github.com/Tokemak/v2-core/issues/696
        assertEq(lockup0.amount, 0);
        assertEq(lockup0.points, 0);

        // try extend to 2 years
        uint256[] memory durations = new uint256[](1);
        durations[0] = 2 * ONE_YEAR;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "oldEnd"));
        accToke.extend(lockupIds, durations);
    }

    function test_Revert_IfAmountIsInsufficient() public {
        accToke.stake(stakeAmount, ONE_YEAR);
        weth.approve(address(accToke), 1);

        vm.expectRevert(abi.encodeWithSelector(IAccToke.InsufficientAmount.selector));
        accToke.addWETHRewards(1);
    }

    /* **************************************************************************** */
    /* 						Staking helper methods									*/

    function stake(uint256 amount, uint256 stakeTimespan) private {
        stake(amount, stakeTimespan, address(this));
    }

    function stake(uint256 amount, uint256 stakeTimespan, address user) private {
        vm.assume(amount > 0 && amount < MAX_STAKE_AMOUNT);

        (uint256 points, uint256 end) = accToke.previewPoints(amount, stakeTimespan);
        vm.expectEmit(true, false, false, false);
        emit Stake(user, 0, amount, end, points);
        accToke.stake(amount, stakeTimespan);
    }

    function warpAndStake(uint256 amount, uint256 warpTimespan, uint256 stakeTimespan) private {
        vm.warp(block.timestamp + warpTimespan);
        vm.expectEmit(true, false, false, false);
        emit Stake(address(this), 0, 0, 0, 0);
        accToke.stake(amount, stakeTimespan);
    }

    function warpAndUnstake(uint256 warpTimespan, uint256 lockupId) private {
        vm.expectEmit(true, false, false, false);
        emit Unstake(address(this), 0, 0, 0, 0);
        vm.warp(block.timestamp + warpTimespan);
        uint256[] memory lockupIds = new uint256[](1);
        lockupIds[0] = lockupId;
        accToke.unstake(lockupIds);
    }

    /* **************************************************************************** */
    /* 									Rewards										*/
    /* **************************************************************************** */

    function test_StakingRewards_SingleUser_OneStake(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);
        address user1 = address(this);

        // stake toke for a year
        stake(amount, ONE_YEAR);
        assertEq(accToke.totalRewardsEarned(), 0, "No rewards yet");
        assertEq(accToke.totalRewardsClaimed(), 0);
        assertEq(accToke.previewRewards(), 0);
        // add new rewards
        topOffRewards(amount);
        // make sure we can claim now
        assertApproxEqRel(accToke.totalRewardsEarned(), amount, TOLERANCE);
        assertEq(accToke.totalRewardsClaimed(), 0);
        assertApproxEqRel(accToke.previewRewards(), amount, TOLERANCE, "Full reward not showing up as available");
        // claim rewards
        collectRewards(user1);
        // make sure: a) no more left to claim, b) claim was logged properly
        assertApproxEqRel(accToke.totalRewardsEarned(), amount, TOLERANCE);
        assertApproxEqRel(accToke.totalRewardsClaimed(), amount, TOLERANCE);
        assertEq(accToke.previewRewards(), 0, "Should have no more rewards to claim");
        assertApproxEqRel(accToke.rewardsClaimed(address(this)), amount, TOLERANCE);
    }

    function test_StakingRewards_SingleUser_OneStakeClaimRewardsOnBehalfOfUser(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount);
        address user1 = address(this);

        // stake toke for a year
        stake(amount, ONE_YEAR);
        assertEq(accToke.totalRewardsEarned(), 0, "No rewards yet");
        assertEq(accToke.totalRewardsClaimed(), 0);
        assertEq(accToke.previewRewards(), 0);
        // add new rewards
        topOffRewards(amount);
        // make sure we can claim now
        assertApproxEqRel(accToke.totalRewardsEarned(), amount, TOLERANCE);
        assertEq(accToke.totalRewardsClaimed(), 0);
        assertApproxEqRel(accToke.previewRewards(), amount, TOLERANCE, "Full reward not showing up as available");

        //Rewards can be claimed on behalf of user by
        // 1. user itself
        // 2. router
        collectRewardsOnBehalfOfUser(user1);
        // make sure: a) no more left to claim, b) claim was logged properly
        assertApproxEqRel(accToke.totalRewardsEarned(), amount, TOLERANCE);
        assertApproxEqRel(accToke.totalRewardsClaimed(), amount, TOLERANCE);
        assertEq(accToke.previewRewards(), 0, "Should have no more rewards to claim");
        assertApproxEqRel(accToke.rewardsClaimed(address(this)), amount, TOLERANCE);
    }

    function test_CollectRewardsOnBehalfOfUser_InvalidCollector() public {
        address randomUser = address(2);
        address router = address(systemRegistry.autoPoolRouter());

        //A random user cannot collect rewards on behalf of user
        vm.startPrank(randomUser);
        address user = address(this);
        vm.expectRevert(Errors.AccessDenied.selector);
        accToke.collectRewards(user, router);

        vm.stopPrank();

        //User cannot claim rewards for zero address.
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "recipient"));
        accToke.collectRewards(user, address(0));
    }

    function test_StakingRewards_SingleUser_MultipleStakes(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount * 2); // "*2" in order to account for reward topping up

        address user1 = address(this);
        // stake toke for 2 years
        stake(amount, ONE_YEAR);
        // make sure we can't cash anything yet
        assertEq(accToke.previewRewards(), 0, "Shouldn't have any rewards yet to claim");

        // add new rewards
        topOffRewards(amount);
        // make sure we can claim now
        assertApproxEqRel(accToke.previewRewards(), amount, TOLERANCE, "Incorrect new rewards amount");

        // forward a year
        skip(ONE_YEAR);

        stake(amount, ONE_YEAR);
        topOffRewards(amount);
        // verify that only old rewards can be accessed
        assertApproxEqRel(accToke.previewRewards(), 2 * amount, TOLERANCE, "Incorrect second rewards amount");

        // claim rewards
        collectRewards(user1);
        // make sure: a) no more left to claim, b) claim was logged properly
        assertEq(accToke.previewRewards(), 0, "should have no more rewards left to claim");
        assertApproxEqRel(
            accToke.rewardsClaimed(address(this)), 2 * amount, TOLERANCE, "claim rewards amount does not match"
        );
    }

    function test_StakingRewards_MultiUser(
        uint256 amount
    ) public {
        _checkFuzz(amount);

        prepareFunds(address(this), amount * 3); // "*3" in order to account for reward topping up

        //
        // Stakes for user 1

        // add awards (just to have original pot)
        address user1 = address(this);
        vm.label(user1, "user1");

        // stake toke for 2 years
        stake(amount, 2 * ONE_YEAR, user1);
        // make sure we can't cash anything yet
        assertEq(accToke.previewRewards(), 0, "Shouldn't have any rewards yet to claim");

        // ////////////////////
        // add new rewards
        topOffRewards(amount);

        // make sure we can claim now
        assertApproxEqRel(accToke.previewRewards(user1), amount, TOLERANCE, "Incorrect new rewards amount");

        // forward a year
        skip(ONE_YEAR);

        //
        // stake as user 2
        //
        address user2 = createAndPrankUser("user2", amount);
        prepareFunds(user2, amount);
        stake(amount, ONE_YEAR, user2);

        // make sure user2 has no rewards yet (even though user1 does)
        assertApproxEqRel(accToke.previewRewards(user1), amount, TOLERANCE);
        assertApproxEqRel(accToke.previewRewards(user2), 0, TOLERANCE);

        vm.startPrank(user1);
        topOffRewards(amount);

        // verify rewards
        assertApproxEqRel(accToke.previewRewards(user1), amount * 3 / 2, TOLERANCE);
        assertApproxEqRel(accToke.previewRewards(user2), amount / 2, TOLERANCE);

        // claim rewards
        collectRewards(user1);
        collectRewards(user2);

        assertApproxEqRel(accToke.previewRewards(user1), 0, TOLERANCE);
        assertApproxEqRel(accToke.rewardsClaimed(user1), amount * 3 / 2, TOLERANCE);
        assertApproxEqRel(accToke.previewRewards(user2), 0, TOLERANCE);
        assertApproxEqRel(accToke.rewardsClaimed(user2), amount / 2, TOLERANCE);
    }

    /* **************************************************************************** */
    /* 									Admin unlock										*/
    /* **************************************************************************** */
    function test_setAdminUnlock_RevertIf_CallerDoesNotHaveRole() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        vm.prank(address(1));
        accToke.setAdminUnlock();
    }

    function test_setAdminUnlock_RunsProperly() public {
        vm.expectEmit(true, true, true, true);
        emit AdminUnlockSet(true);
        accToke.setAdminUnlock();
        assertEq(accToke.adminUnlock(), true);
    }

    function test_setAdminUnlock_RevertIf_AlreadySet() public {
        accToke.setAdminUnlock();
        assertEq(accToke.adminUnlock(), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector, "adminUnlock"));
        accToke.setAdminUnlock();
    }

    function test_stake_RevertIf_AdminUnlockTrue() public {
        uint256 stakeTime = 100 days;
        address user1 = makeAddr("user1");

        prepareFunds(address(this), stakeAmount);

        // Flip flag
        accToke.setAdminUnlock();
        assertEq(accToke.adminUnlock(), true);

        // Attempt to stake
        vm.expectRevert(IAccToke.AdminUnlockActive.selector);
        accToke.stake(stakeAmount, stakeTime, user1);

        vm.expectRevert(IAccToke.AdminUnlockActive.selector);
        accToke.stake(stakeAmount, stakeTime);
    }

    function test_extend_RevertIf_AdminUnlockTrue() public {
        uint256 stakeTime = 100 days;

        prepareFunds(address(this), stakeAmount);

        accToke.stake(stakeAmount, stakeTime);

        // Flip flag
        accToke.setAdminUnlock();
        assertEq(accToke.adminUnlock(), true);

        // Warp so it makes sense to extend
        vm.warp(block.timestamp + 50 days);

        // Attempt to extend
        uint256[] memory lockupIds = new uint256[](1);
        uint256[] memory extendDurations = new uint256[](1);
        extendDurations[0] = stakeTime;

        vm.expectRevert(IAccToke.AdminUnlockActive.selector);
        accToke.extend(lockupIds, extendDurations);
    }

    function test_EarlyUnlock_ProperRewards_AdminUnlockTrue() public {
        // Deposit
        prepareFunds(address(this), stakeAmount);
        accToke.stake(stakeAmount, 100 days);

        // Queue rewards
        accToke.addWETHRewards(1 ether);

        // Ensure user has balance
        (uint128 lockAmountBefore, uint128 lockEndBefore, uint256 pointsBefore) = accToke.lockups(address(this), 0);
        assertEq(lockAmountBefore, stakeAmount);

        // Ensure that timestamp less than end of lock
        assertGt(lockEndBefore, block.timestamp);

        // Snapshot rewards info - Paid in weth
        uint256 rewardsBefore = accToke.previewRewards(address(this));
        uint256 wethBalanceBefore = weth.balanceOf(address(this));

        // Flip flag
        accToke.setAdminUnlock();
        assertEq(accToke.adminUnlock(), true);

        // Withdraw, ensure that end time updated to block timestamp in event
        uint256[] memory lockups = new uint256[](1);
        uint256 userTokeBalanceBefore = toke.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit Unstake(address(this), 0, stakeAmount, block.timestamp, pointsBefore);
        accToke.unstake(lockups);

        // Check balance of user, lock deleted
        (uint128 lockAmountAfter, uint128 lockEndAfter, uint256 pointsAfter) = accToke.lockups(address(this), 0);
        assertEq(lockAmountAfter, 0);
        assertEq(lockEndAfter, 0);
        assertEq(pointsAfter, 0);
        assertEq(toke.balanceOf(address(this)), userTokeBalanceBefore + stakeAmount);

        // Collect rewards and check that amount collected is what is expected
        accToke.collectRewards();
        assertEq(weth.balanceOf(address(this)), wethBalanceBefore + rewardsBefore);
    }

    function test_RevertIf_EarlyUnlock_AdminUnlockFalse() public {
        uint256 lockTime = 100 days;
        uint256 snapshotTimestamp = block.timestamp;

        // Deposit
        prepareFunds(address(this), stakeAmount);
        accToke.stake(stakeAmount, lockTime);

        (, uint128 lockEnd,) = accToke.lockups(address(this), 0);
        assertEq(lockEnd, block.timestamp + lockTime);

        // Try to unstake without admin flag being flipped, no time change
        assertEq(accToke.adminUnlock(), false);
        vm.expectRevert(IAccToke.NotUnlockableYet.selector);

        uint256[] memory unlockIds = new uint256[](1);
        accToke.unstake(unlockIds);

        // Warp timestamp to unlock
        vm.warp(snapshotTimestamp + lockTime);

        // unstake and checks
        assertGt(accToke.balanceOf(address(this)), 0);
        accToke.unstake(unlockIds);
        assertEq(accToke.balanceOf(address(this)), 0);
    }

    /* **************************************************************************** */
    /* 						Rewards helper methods									*/

    // @dev Top off rewards to make sure there is enough to claim
    function topOffRewards(
        uint256 _amount
    ) private {
        vm.assume(_amount < MAX_REWARD_ADD);

        // get some weth if not enough to top off rewards
        if (weth.balanceOf(address(this)) < _amount) {
            deal(address(weth), address(this), _amount);
        }

        uint256 wethStakingBalanceBefore = weth.balanceOf(address(accToke));

        weth.approve(address(accToke), _amount);

        vm.expectEmit(true, true, false, false);
        emit RewardsAdded(_amount, 0);
        accToke.addWETHRewards(_amount);

        assertEq(weth.balanceOf(address(accToke)), wethStakingBalanceBefore + _amount);
    }

    function collectRewards(
        address user
    ) private {
        vm.startPrank(user);

        uint256 claimTargetAmount = accToke.previewRewards();

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(user, user, claimTargetAmount);
        accToke.collectRewards();

        vm.stopPrank();
    }

    function collectRewardsOnBehalfOfUser(
        address user
    ) private {
        address router = address(systemRegistry.autoPoolRouter());
        vm.startPrank(router);

        uint256 claimTargetAmount = accToke.previewRewards(user);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(user, router, claimTargetAmount);
        accToke.collectRewards(user, router);

        vm.stopPrank();
    }

    function prepareFunds(address user, uint256 amount) private {
        vm.startPrank(user);

        deal(address(toke), user, amount);
        toke.approve(address(accToke), amount);
        deal(address(weth), user, amount);
        weth.approve(address(accToke), amount);
    }

    function _checkFuzz(
        uint256 amount
    ) private {
        vm.assume(amount >= 10_000 && amount <= MAX_STAKE_AMOUNT);

        // adjust tolerance for small amounts to account for rounding errors
        if (amount < 100_000) {
            TOLERANCE = 1e16;
        }
    }
}
