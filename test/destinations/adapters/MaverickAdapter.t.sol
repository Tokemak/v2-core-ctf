// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import { IRouter } from "src/interfaces/external/maverick/IRouter.sol";
import { MaverickAdapter } from "src/destinations/adapters/MaverickAdapter.sol";
import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { IPosition } from "src/interfaces/external/maverick/IPosition.sol";
import { IRouter } from "src/interfaces/external/maverick/IRouter.sol";
import {
    WSTETH_MAINNET,
    MAV_ROUTER,
    CBETH_MAINNET,
    WETH_MAINNET,
    MAV_WSTETH_WETH_POOL,
    SWETH_MAINNET
} from "test/utils/Addresses.sol";

contract MaverickAdapterTest is Test {
    struct MaverickDeploymentExtraParams {
        address poolAddress;
        uint256 tokenId;
        uint256 deadline;
        IPool.AddLiquidityParams[] maverickParams;
    }

    struct MaverickWithdrawalExtraParams {
        address poolAddress;
        uint256 tokenId;
        uint256 deadline;
        IPool.RemoveLiquidityParams[] maverickParams;
    }

    // solhint-disable-next-line var-name-mixedcase
    uint256 private INITIAL_TOKEN_ID = 0;

    uint256 private mainnetFork;
    IRouter private router;
    IPosition private position;

    ///@dev Implementing this function to receive Maverick Position NFT on deposit
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_528_181);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        router = IRouter(MAV_ROUTER);
        position = router.position();
    }

    // wstETH/WETH
    function testRemoveLiquidityWethWstEth() public {
        IPool pool = IPool(MAV_WSTETH_WETH_POOL);

        uint256[] memory amounts = new uint256[](2);
        uint128 deltaA = 5 * 1e18;
        uint128 deltaB = 5 * 1e18;
        amounts[0] = 1 * 1e18;
        amounts[1] = 1 * 1e18;

        deal(address(WETH_MAINNET), address(this), 10 * 1e18);
        deal(address(WSTETH_MAINNET), address(this), 10 * 1e18);

        IPool.AddLiquidityParams[] memory maverickParams = new IPool.AddLiquidityParams[](1);
        maverickParams[0] = IPool.AddLiquidityParams(3, 0, true, deltaA, deltaB);

        bytes memory extraParams =
            abi.encode(MaverickDeploymentExtraParams(address(pool), INITIAL_TOKEN_ID, 1e13, maverickParams));

        _addLiquidity(router, amounts, extraParams);

        uint128 binId = 53;
        uint256 withDrawTokenId = position.tokenOfOwnerByIndex(address(this), 0);

        uint256 preBalanceA = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 preBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = pool.balanceOf(withDrawTokenId, binId);

        IPool.RemoveLiquidityParams[] memory maverickWithdrawalParams = new IPool.RemoveLiquidityParams[](1);
        maverickWithdrawalParams[0] = IPool.RemoveLiquidityParams(binId, uint128(preLpBalance));

        bytes memory extraWithdrawalParams =
            abi.encode(MaverickWithdrawalExtraParams(address(pool), withDrawTokenId, 1e13, maverickWithdrawalParams));

        MaverickAdapter.removeLiquidity(router, amounts, preLpBalance, extraWithdrawalParams);

        uint256 afterBalanceA = IERC20(WSTETH_MAINNET).balanceOf(address(this));
        uint256 afterBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 aftrerLpBalance = pool.balanceOf(withDrawTokenId, binId);

        assertTrue(afterBalanceA > preBalanceA);
        assertTrue(afterBalanceB > preBalanceB);
        assert(aftrerLpBalance < preLpBalance);
    }

    // cbETH/WETH
    function testAddLiquidityWethCbEth() public {
        IPool pool = IPool(0xa495a38Ea3728aC29096c86CA30127003f33AF28);

        uint256[] memory amounts = new uint256[](2);
        uint128 deltaA = 5 * 1e18;
        uint128 deltaB = 5 * 1e18;
        amounts[0] = 1 * 1e18;
        amounts[1] = 1 * 1e18;

        deal(address(WETH_MAINNET), address(this), 10 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 10 * 1e18);

        uint128 binId = 19;

        uint256 preBalanceA = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = pool.balanceOf(INITIAL_TOKEN_ID, binId);

        IPool.AddLiquidityParams[] memory maverickParams = new IPool.AddLiquidityParams[](1);
        maverickParams[0] = IPool.AddLiquidityParams(3, 0, true, deltaA, deltaB);

        bytes memory extraParams =
            abi.encode(MaverickDeploymentExtraParams(address(pool), INITIAL_TOKEN_ID, 1e13, maverickParams));

        _addLiquidity(router, amounts, extraParams);

        uint256 afterBalanceA = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));

        uint256 tokenId = position.tokenOfOwnerByIndex(address(this), 0);
        uint256 aftrerLpBalance = pool.balanceOf(tokenId, binId);

        assertTrue(afterBalanceA < preBalanceA);
        assertTrue(afterBalanceB < preBalanceB);
        assert(aftrerLpBalance > preLpBalance);
    }

    // cbETH/WETH
    function testRemoveLiquidityWethCbEth() public {
        IPool pool = IPool(0xa495a38Ea3728aC29096c86CA30127003f33AF28);

        uint256[] memory amounts = new uint256[](2);
        uint128 deltaA = 5 * 1e18;
        uint128 deltaB = 5 * 1e18;
        amounts[0] = 1;
        amounts[1] = 1;

        deal(address(WETH_MAINNET), address(this), 10 * 1e18);
        deal(address(CBETH_MAINNET), address(this), 10 * 1e18);

        IPool.AddLiquidityParams[] memory maverickParams = new IPool.AddLiquidityParams[](1);
        maverickParams[0] = IPool.AddLiquidityParams(3, 0, true, deltaA, deltaB);

        bytes memory extraParams =
            abi.encode(MaverickDeploymentExtraParams(address(pool), INITIAL_TOKEN_ID, 1e13, maverickParams));

        _addLiquidity(router, amounts, extraParams);

        uint128 binId = 19;
        uint256 withDrawTokenId = position.tokenOfOwnerByIndex(address(this), 0);

        uint256 preBalanceA = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 preBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = pool.balanceOf(withDrawTokenId, binId);

        IPool.RemoveLiquidityParams[] memory maverickWithdrawalParams = new IPool.RemoveLiquidityParams[](1);
        maverickWithdrawalParams[0] = IPool.RemoveLiquidityParams(binId, uint128(preLpBalance));

        bytes memory extraWithdrawalParams =
            abi.encode(MaverickWithdrawalExtraParams(address(pool), withDrawTokenId, 1e13, maverickWithdrawalParams));

        MaverickAdapter.removeLiquidity(router, amounts, preLpBalance, extraWithdrawalParams);

        uint256 afterBalanceA = IERC20(CBETH_MAINNET).balanceOf(address(this));
        uint256 afterBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 aftrerLpBalance = pool.balanceOf(withDrawTokenId, binId);

        assertTrue(afterBalanceA > preBalanceA);
        assertTrue(afterBalanceB > preBalanceB);
        assert(aftrerLpBalance < preLpBalance);
    }

    // swETH/WETH
    function testAddLiquiditySwEthWeth() public {
        IPool pool = IPool(0x0CE176E1b11A8f88a4Ba2535De80E81F88592bad);

        uint256[] memory amounts = new uint256[](2);
        uint128 deltaA = 50 * 1e18;
        uint128 deltaB = 50 * 1e18;
        amounts[0] = 1 * 1e18;
        amounts[1] = 1 * 1e18;

        deal(address(SWETH_MAINNET), address(this), 100 * 1e18);
        deal(address(WETH_MAINNET), address(this), 100 * 1e18);

        uint128 binId = 12;

        uint256 preBalanceA = IERC20(SWETH_MAINNET).balanceOf(address(this));
        uint256 preBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = pool.balanceOf(INITIAL_TOKEN_ID, binId);

        IPool.AddLiquidityParams[] memory maverickParams = new IPool.AddLiquidityParams[](1);
        maverickParams[0] = IPool.AddLiquidityParams(3, 0, true, deltaA, deltaB);

        bytes memory extraParams =
            abi.encode(MaverickDeploymentExtraParams(address(pool), INITIAL_TOKEN_ID, 1e13, maverickParams));

        _addLiquidity(router, amounts, extraParams);

        uint256 afterBalanceA = IERC20(SWETH_MAINNET).balanceOf(address(this));
        uint256 afterBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));

        uint256 tokenId = position.tokenOfOwnerByIndex(address(this), 0);
        uint256 aftrerLpBalance = pool.balanceOf(tokenId, binId);

        assertTrue(afterBalanceA < preBalanceA);
        assertTrue(afterBalanceB < preBalanceB);
        assert(aftrerLpBalance > preLpBalance);
    }

    // swETH/WETH
    function testRemoveLiquiditySwEthWeth() public {
        IPool pool = IPool(0x0CE176E1b11A8f88a4Ba2535De80E81F88592bad);

        uint256[] memory amounts = new uint256[](2);
        uint128 deltaA = 50 * 1e18;
        uint128 deltaB = 50 * 1e18;
        amounts[0] = 1 * 1e18;
        amounts[1] = 1 * 1e18;

        deal(address(SWETH_MAINNET), address(this), 100 * 1e18);
        deal(address(WETH_MAINNET), address(this), 100 * 1e18);

        IPool.AddLiquidityParams[] memory maverickParams = new IPool.AddLiquidityParams[](1);
        maverickParams[0] = IPool.AddLiquidityParams(3, 0, true, deltaA, deltaB);

        bytes memory extraParams =
            abi.encode(MaverickDeploymentExtraParams(address(pool), INITIAL_TOKEN_ID, 1e13, maverickParams));

        _addLiquidity(router, amounts, extraParams);

        uint128 binId = 12;
        uint256 withDrawTokenId = position.tokenOfOwnerByIndex(address(this), 0);

        uint256 preBalanceA = IERC20(SWETH_MAINNET).balanceOf(address(this));
        uint256 preBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 preLpBalance = pool.balanceOf(withDrawTokenId, binId);

        IPool.RemoveLiquidityParams[] memory maverickWithdrawalParams = new IPool.RemoveLiquidityParams[](1);
        maverickWithdrawalParams[0] = IPool.RemoveLiquidityParams(binId, uint128(preLpBalance));

        bytes memory extraWithdrawalParams =
            abi.encode(MaverickWithdrawalExtraParams(address(pool), withDrawTokenId, 1e13, maverickWithdrawalParams));

        MaverickAdapter.removeLiquidity(router, amounts, preLpBalance, extraWithdrawalParams);

        uint256 afterBalanceA = IERC20(SWETH_MAINNET).balanceOf(address(this));
        uint256 afterBalanceB = IERC20(WETH_MAINNET).balanceOf(address(this));
        uint256 aftrerLpBalance = pool.balanceOf(withDrawTokenId, binId);

        assertTrue(afterBalanceA > preBalanceA);
        assertTrue(afterBalanceB > preBalanceB);
        assert(aftrerLpBalance < preLpBalance);
    }

    function _addLiquidity(IRouter _router, uint256[] memory amounts, bytes memory extraParams) private {
        (MaverickDeploymentExtraParams memory maverickExtraParams) =
            abi.decode(extraParams, (MaverickDeploymentExtraParams));
        _approveTokens(_router, maverickExtraParams);
        _router.addLiquidityToPool(
            IPool(maverickExtraParams.poolAddress),
            maverickExtraParams.tokenId,
            maverickExtraParams.maverickParams,
            amounts[0],
            amounts[1],
            maverickExtraParams.deadline
        );
    }

    function _approveTokens(IRouter _router, MaverickDeploymentExtraParams memory maverickExtraParams) private {
        IPool.AddLiquidityParams[] memory maverickParams = maverickExtraParams.maverickParams;

        uint256[] memory approvalSummary = new uint256[](2);
        for (uint256 i = 0; i < maverickParams.length; ++i) {
            approvalSummary[0] += maverickParams[i].deltaA;
            approvalSummary[1] += maverickParams[i].deltaB;
        }
        LibAdapter._approve(IPool(maverickExtraParams.poolAddress).tokenA(), address(_router), approvalSummary[0]);
        LibAdapter._approve(IPool(maverickExtraParams.poolAddress).tokenB(), address(_router), approvalSummary[1]);
    }
}
