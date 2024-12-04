// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import {
    WETH_MAINNET,
    ETHERFI_LRTSQUARED_CLAIM,
    SYSTEM_REGISTRY_MAINNET,
    ZERO_EX_SWAPPER_MAINNET,
    LRTSQUARED_MAINNET,
    TREASURY
} from "test/utils/Addresses.sol";

import { EtherFiClaimingDestinationVaultExtension } from
    "src/vault/extensions/EtherFiClaimingDestinationVaultExtension.sol";
import { BaseClaimingDestinationVaultExtension } from
    "src/vault/extensions/base/BaseClaimingDestinationVaultExtension.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// solhint-disable const-name-snakecase,max-line-length,func-name-mixedcase

contract EtherFiClaimingDestinationVaultExtensionTest is Test {
    bytes public constant swapDataAtPinnedBlock =
        hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000002d7af65e5d5060000000000000000000000000000000000000000000000000001f292c872c64df40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b8f08b70456eb22f6109f57b8fafe862ed28e6040002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000003b5689d9cecb0143f9c5c460";

    // Swap and claim amount are known
    uint256 public constant wethAmountReceived = 141_753_462_645_070_618;
    uint256 public constant claimAmount = 204_825_160_251_147_776;

    IDestinationVault public constant dv = IDestinationVault(0x148Ca723BefeA7b021C399413b8b7426A4701500);
    ISystemRegistry public constant systemRegistry = ISystemRegistry(SYSTEM_REGISTRY_MAINNET);
    address public constant etherFiClaim = ETHERFI_LRTSQUARED_CLAIM;
    address public constant zeroExSwapper = ZERO_EX_SWAPPER_MAINNET;
    IERC20 public constant lrtSquaredToken = IERC20(LRTSQUARED_MAINNET);
    IERC20 public constant wethERC20 = IERC20(WETH_MAINNET);

    EtherFiClaimingDestinationVaultExtension public extension;

    event ClaimingExtensionExecuted(uint256[] amountsClaimed, address[] tokensClaimed, uint256 amountAddedToRewards);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_066_621);

        extension = new EtherFiClaimingDestinationVaultExtension(
            systemRegistry, zeroExSwapper, etherFiClaim, address(lrtSquaredToken)
        );

        // Give test contract the ability to set and execute extensions
        vm.startPrank(TREASURY);
        systemRegistry.accessController().setupRole(Roles.DESTINATION_VAULT_MANAGER, address(this));
        systemRegistry.accessController().setupRole(Roles.DV_REWARD_MANAGER, address(this));
        vm.stopPrank();

        // Add DV to whitelist for rewarder
        IBaseRewarder(dv.rewarder()).addToWhitelist(address(dv));

        // Set extension
        dv.setExtension(address(extension));

        // Warp timestamp
        vm.warp(block.timestamp + 7 days);
    }

    function _getExtensionData(
        uint256 expectedClaim
    ) internal view returns (BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory dataStruct) {
        bytes32[] memory merkleProof = new bytes32[](19);
        SwapParams[] memory swapParams = new SwapParams[](1);

        merkleProof[0] = 0xf3ac04bec50c092ca4eb545094d4ff66e2a8b866ae3d9d682c618ff506a8bda9;
        merkleProof[1] = 0x58f181f60d49d61d81cd3bd26731c6d91d09e17b948746074f88d03ed7eb2d1f;
        merkleProof[2] = 0x0b3c8736fc3c6fe3222f821c0b30abc36f738632b227a8ce81146db59e23c81f;
        merkleProof[3] = 0x5adbc8a808deb87a21cf22f370ccc9431957ece8efefa036d29426ba42ea0e6f;
        merkleProof[4] = 0xc49284929d393033aac21f62200692e68c118cadecdd8df0f2600ddef46c74b2;
        merkleProof[5] = 0x7e42a9839c24d907543852fe4b9f962ab372800ab9ebe81a35c2b77c913c0524;
        merkleProof[6] = 0xa367e56fc5c07fe01be69bdedfc3004515dbf5039026e6a5ba827c5b27da117e;
        merkleProof[7] = 0x49c19a86331556e3df19fdc5f88608d59bc5926a5da44b1a4512d0a086a9363b;
        merkleProof[8] = 0xa0e28bc2f5c2b26e461787ce6a45e0c5e3b1e23a7de6ae82db83a4b2cdac27d1;
        merkleProof[9] = 0xc9d6622429f85ca6e9bd2b3d4376fc08de9d820ae9014de1bf7c4ea180629e5d;
        merkleProof[10] = 0x9bc70b417f2ea689d907d7dbf3b48810de959c4fe5caff16bf25ef7a7bebc110;
        merkleProof[11] = 0x9ccd90144c05d42b91e9f0ed5b23aec0a96449393ff3ed8ec73f1c8cc148262c;
        merkleProof[12] = 0x429db03e57767743f17e4b95e63b8be498a0cf582c48b395b6478b4e7f30680d;
        merkleProof[13] = 0xcef0ff27f1d2529b5647f8eb8516d5045448105ce0d5cf41f603d08687777335;
        merkleProof[14] = 0x1f96cc5fb66515eca110445be482de86feca4e7dbbc20b54faf28efbebe13fbb;
        merkleProof[15] = 0x6c125357b0bb881e440809c6cbe13fc9b0b48cfe77dcd67c25605c752e5cc85d;
        merkleProof[16] = 0x1a8bd4f9bffd172773ac2c1446b5d3dd927c4d6d79fef472d0d1c54da4d8c740;
        merkleProof[17] = 0x5cb70c9b5a9153ec927ef61b36fcb117e1fe842aae8126dfd860a47a8559538f;
        merkleProof[18] = 0x429837e8dbb22a1a02ffe5665ce70f4efeb2f3d312b8866cd02cd09045c444de;

        EtherFiClaimingDestinationVaultExtension.EtherFiClaimParams memory claimParams =
        EtherFiClaimingDestinationVaultExtension.EtherFiClaimParams({
            account: address(dv),
            cumulativeAmount: claimAmount,
            expectedClaimAmount: expectedClaim,
            expectedMerkleRoot: 0x1fbf9f01fb67f0627166a40a96bdb5f0f9aa040bcf2e6bf28bd47b70eb3325f8,
            merkleProof: merkleProof
        });

        swapParams[0] = SwapParams({
            sellTokenAddress: address(lrtSquaredToken),
            sellAmount: claimAmount,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: 140_000_000_000_000_000,
            data: swapDataAtPinnedBlock,
            extraData: bytes(""),
            deadline: block.timestamp
        });

        dataStruct = BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams({
            sendToRewarder: true,
            claimData: abi.encode(claimParams),
            swapParams: swapParams
        });
    }
}

contract EtherFiDVExtensionConstructorTest is EtherFiClaimingDestinationVaultExtensionTest {
    function test_RevertsWhenZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_claimContract"));
        new EtherFiClaimingDestinationVaultExtension(
            systemRegistry, zeroExSwapper, address(0), address(lrtSquaredToken)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_claimToken"));
        new EtherFiClaimingDestinationVaultExtension(systemRegistry, zeroExSwapper, etherFiClaim, address(0));
    }

    function test_StateSet() public {
        assertEq(address(extension.claimToken()), address(lrtSquaredToken));
        assertEq(address(extension.claimContract()), etherFiClaim);
    }
}

contract EtherFiDVExtensionExecuteTest is EtherFiClaimingDestinationVaultExtensionTest {
    function test_RevertIf_claimAmount_Zero() public {
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params = _getExtensionData(0);

        bytes memory data = abi.encode(params);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "expectedClaimAmount"));
        dv.executeExtension(data);
    }

    function test_RevertIf_ClaimAmount_And_ExpectedAmount_AreNotEqual() public {
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params = _getExtensionData(10);

        bytes memory data = abi.encode(params);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseClaimingDestinationVaultExtension.InvalidAmountReceived.selector, claimAmount, 10
            )
        );
        dv.executeExtension(data);
    }

    function test_RunsProperly() public {
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params = _getExtensionData(claimAmount);

        bytes memory data = abi.encode(params);

        uint256 dvWethBefore = wethERC20.balanceOf(address(dv));
        uint256 dvRewarderWethBefore = wethERC20.balanceOf(dv.rewarder());
        uint256 addressThisWethBefore = wethERC20.balanceOf(address(this));

        uint256[] memory amountsClaimed = new uint256[](1);
        address[] memory tokensClaimed = new address[](1);

        amountsClaimed[0] = claimAmount;
        tokensClaimed[0] = address(lrtSquaredToken);

        vm.expectEmit(true, true, true, true);
        emit ClaimingExtensionExecuted(amountsClaimed, tokensClaimed, wethAmountReceived);
        dv.executeExtension(data);

        assertEq(wethERC20.balanceOf(dv.rewarder()), dvRewarderWethBefore + wethAmountReceived);
        assertEq(wethERC20.balanceOf(address(dv)), dvWethBefore);
        assertEq(wethERC20.balanceOf(address(this)), addressThisWethBefore);
        assertEq(lrtSquaredToken.balanceOf(address(this)), 0);
    }

    function test_RunsProperly_SendsToCaller() public {
        BaseClaimingDestinationVaultExtension.BaseClaimingExtensionParams memory params = _getExtensionData(claimAmount);
        params.sendToRewarder = false;
        bytes memory data = abi.encode(params);

        uint256 dvWethBefore = wethERC20.balanceOf(address(dv));
        uint256 dvRewarderWethBefore = wethERC20.balanceOf(dv.rewarder());
        uint256 addressThisWethBefore = wethERC20.balanceOf(address(this));

        uint256[] memory amountsClaimed = new uint256[](1);
        address[] memory tokensClaimed = new address[](1);

        amountsClaimed[0] = claimAmount;
        tokensClaimed[0] = address(lrtSquaredToken);

        vm.expectEmit(true, true, true, true);
        emit ClaimingExtensionExecuted(amountsClaimed, tokensClaimed, wethAmountReceived);
        dv.executeExtension(data);

        assertEq(wethERC20.balanceOf(dv.rewarder()), dvRewarderWethBefore);
        assertEq(wethERC20.balanceOf(address(this)), addressThisWethBefore + wethAmountReceived);
        assertEq(wethERC20.balanceOf(address(dv)), dvWethBefore);
        assertEq(lrtSquaredToken.balanceOf(address(this)), 0);
    }
}
