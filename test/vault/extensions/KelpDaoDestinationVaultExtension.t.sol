// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import {
    WETH_MAINNET,
    KELPDAO_EIGEN_CLAIM,
    SYSTEM_REGISTRY_MAINNET,
    ZERO_EX_SWAPPER_MAINNET,
    EIGEN_MAINNET,
    TREASURY
} from "test/utils/Addresses.sol";

import { KelpDaoDestinationVaultExtension } from "src/vault/extensions/KelpDaoDestinationVaultExtension.sol";
import { BaseDestinationVaultExtension } from "src/vault/extensions/base/BaseDestinationVaultExtension.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { IBaseRewarder } from "src/interfaces/rewarders/IBaseRewarder.sol";
import { Errors } from "src/utils/Errors.sol";
import { Roles } from "src/libs/Roles.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// solhint-disable const-name-snakecase,max-line-length,func-name-mixedcase

contract KelpDaoDestinationVaultExtensionTest is Test {
    bytes public constant swapDataAtPinnedBlock =
        hex"6af479b20000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000032081f6141f18226e30000000000000000000000000000000000000000000000000e7585fa69df07480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bec53bf9167f50cdeb3ae105f56099aaab9061f83000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000000000000051f7b1af0e3b21d583d560a9";

    // Swap and claim amount are known
    uint256 public constant wethAmountReceived = 1_052_410_302_394_626_443;
    uint256 public constant claimAmount = 922_922_497_097_911_641_827;

    IDestinationVault public constant dv = IDestinationVault(0x4E12227b350E8f8fEEc41A58D36cE2fB2e2d4575);
    ISystemRegistry public constant systemRegistry = ISystemRegistry(SYSTEM_REGISTRY_MAINNET);
    address public constant kelpDaoClaim = KELPDAO_EIGEN_CLAIM;
    address public constant zeroExSwapper = ZERO_EX_SWAPPER_MAINNET;
    IERC20 public constant eigenToken = IERC20(EIGEN_MAINNET);
    IERC20 public constant wethERC20 = IERC20(WETH_MAINNET);

    KelpDaoDestinationVaultExtension public extension;

    event ExtensionExecuted(uint256[] amountsClaimed, address[] tokensClaimed, uint256 amountAddedToRewards);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_079_081);

        extension =
            new KelpDaoDestinationVaultExtension(systemRegistry, zeroExSwapper, kelpDaoClaim, address(eigenToken));

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
    ) internal view returns (BaseDestinationVaultExtension.BaseExtensionParams memory dataStruct) {
        bytes32[] memory merkleProof = new bytes32[](19);
        SwapParams[] memory swapParams = new SwapParams[](1);

        merkleProof[0] = 0xbc876eb68b2161204627c12617c0826374f0fd3ef21d5fdfb0d6d409b3b7599e;
        merkleProof[1] = 0xd1a52a9088eafdc8c6c0876e988b2c8b0cae6e20832b788ae0cc62be60aebfb5;
        merkleProof[2] = 0xb3035330e50150f5a3907e52bd1199e1eafbe054969598cd8349a4ec6e50c8d2;
        merkleProof[3] = 0x5c08a80c0a18083df049f635607b35ed189603c72b4214466d78866b10fb06c9;
        merkleProof[4] = 0x10c17ccc1a668f17d8dab13143574efe29720fafb3c55e4ad54227e7fccdb5ea;
        merkleProof[5] = 0x35345e6dab1969d22bdf35bd2ce09704ea1624383e916bf6550e54f51416d59b;
        merkleProof[6] = 0xc91e83ffc642e9c963951d806d632919e77b73aef7c8c6df52ddae5e8fc783e2;
        merkleProof[7] = 0x25fe82d6ae156a15f650f388760d531bfae7ca9b0fd385e4d9e74365ff18d078;
        merkleProof[8] = 0xbbd649a022d42e3af06e04957de68f2a36562b55801fdaf77c6a5bf2264a828f;
        merkleProof[9] = 0xbcb52a0bb485df6887a4b694f756553e59a2de818e31b81b971e145fb0cc70e3;
        merkleProof[10] = 0x7130e00f0244516bd7c66fe9d86f9a9eace1e19a5a144285bc018374160fe989;
        merkleProof[11] = 0xe7cf35dfec7728468495ff9f69cb13023d6c82fd7b95a094315edbc54000c852;
        merkleProof[12] = 0x134c3fed6442a061fb6ce045a32448675dc3b64b02294f807505a4ae3da8c6cc;
        merkleProof[13] = 0xf32608644274fcff8bbfd5a69943076c1ee34e0dc96f3a82367981580944572c;
        merkleProof[14] = 0xbbd700671406ff61451a861a95358ddfe95f25c48c88e19c92c5f0154feaaf24;
        merkleProof[15] = 0x066a9e4b46f48d3f6c64b3ce6579e3ca2b86a7a65570188847924fdfbf83971c;
        merkleProof[16] = 0xa2b4f44e0e98623c0778a59fd48b0964f40c0096958f1504b1b79ad520b8e4e2;
        merkleProof[17] = 0x0b4153f9c27fb85b6b98be45428f73e3d86f3d3c589b0b00954f3f45cd051ecd;
        merkleProof[18] = 0x0556bb54a9f39b56bff3a0beba8b4ce86525f3b0e57897630d6f888ff0f42d4a;

        KelpDaoDestinationVaultExtension.KelpDaoClaimParams memory claimParams = KelpDaoDestinationVaultExtension
            .KelpDaoClaimParams({
            account: address(dv),
            cumulativeAmount: claimAmount,
            expectedClaimAmount: expectedClaim,
            index: 1,
            merkleProof: merkleProof
        });

        swapParams[0] = SwapParams({
            sellTokenAddress: address(eigenToken),
            sellAmount: claimAmount,
            buyTokenAddress: WETH_MAINNET,
            buyAmount: 1_000_000_000_000_000_000,
            data: swapDataAtPinnedBlock,
            extraData: bytes(""),
            deadline: block.timestamp
        });

        dataStruct = BaseDestinationVaultExtension.BaseExtensionParams({
            claimData: abi.encode(claimParams),
            swapParams: swapParams
        });
    }
}

contract KelpDaoDVExtensionConstructorTest is KelpDaoDestinationVaultExtensionTest {
    function test_RevertsWhenZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_claimContract"));
        new KelpDaoDestinationVaultExtension(systemRegistry, zeroExSwapper, address(0), address(eigenToken));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_claimToken"));
        new KelpDaoDestinationVaultExtension(systemRegistry, zeroExSwapper, kelpDaoClaim, address(0));
    }

    function test_StateSet() public {
        assertEq(address(extension.claimToken()), address(eigenToken));
        assertEq(address(extension.claimContract()), kelpDaoClaim);
    }
}

contract KelpDaoDVExtensionExecuteTest is KelpDaoDestinationVaultExtensionTest {
    function test_RevertIf_claimAmount_Zero() public {
        BaseDestinationVaultExtension.BaseExtensionParams memory params = _getExtensionData(0);

        bytes memory data = abi.encode(params);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "expectedClaimAmount"));
        dv.executeExtension(data);
    }

    function test_RevertIf_ClaimAmount_And_ExpectedAmount_AreNotEqual() public {
        BaseDestinationVaultExtension.BaseExtensionParams memory params = _getExtensionData(10);

        bytes memory data = abi.encode(params);

        vm.expectRevert(
            abi.encodeWithSelector(BaseDestinationVaultExtension.InvalidAmountReceived.selector, claimAmount, 10)
        );
        dv.executeExtension(data);
    }

    function test_RunsProperly() public {
        BaseDestinationVaultExtension.BaseExtensionParams memory params = _getExtensionData(claimAmount);

        bytes memory data = abi.encode(params);

        uint256 dvWethBefore = wethERC20.balanceOf(address(dv));
        uint256 dvRewarderWethBefore = wethERC20.balanceOf(dv.rewarder());

        uint256[] memory amountsClaimed = new uint256[](1);
        address[] memory tokensClaimed = new address[](1);

        amountsClaimed[0] = claimAmount;
        tokensClaimed[0] = address(eigenToken);

        vm.expectEmit(true, true, true, true);
        emit ExtensionExecuted(amountsClaimed, tokensClaimed, wethAmountReceived);
        dv.executeExtension(data);

        assertEq(wethERC20.balanceOf(dv.rewarder()), dvRewarderWethBefore + wethAmountReceived);
        assertEq(wethERC20.balanceOf(address(dv)), dvWethBefore);
        assertEq(eigenToken.balanceOf(address(this)), 0);
    }
}
