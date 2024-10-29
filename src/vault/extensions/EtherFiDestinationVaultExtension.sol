// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IDestinationVaultExtension } from "src/interfaces/vault/IDestinationVaultExtension.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { ICumulativeMerkleDrop } from "src/interfaces/external/etherfi/ICumulativeMerkleDrop.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IAsyncSwapper, SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/SystemComponent.sol";

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

contract EtherFiDestinationVaultExtension is SystemComponent, ReentrancyGuard, IDestinationVaultExtension {
    using Address for address;

    address public immutable asyncSwapper;
    address public immutable claimAddress;
    IERC20 public immutable claimToken;
    IERC20 public immutable weth;

    error InvalidAmountReceived(uint256 expected, uint256 received);
    error InvalidImplementation(address stored, address current);

    event EtherFiExtensionExecuted(uint256 amountClaimed, uint256 amountAddedToRewards);

    struct EtherFiClaimParams {
        address account;
        uint256 cumulativeAmount;
        bytes32 expectedMerkleRoot;
        bytes32[] merkleProof;
    }

    struct EtherFiDVExtensionParams {
        uint256 expectedClaimAmount;
        EtherFiClaimParams claimParams;
        SwapParams swapParams;
    }

    // address(this) will be the DVs address in a delegatecall context
    modifier onlyDestinationVault() {
        systemRegistry.destinationVaultRegistry().verifyIsRegistered(address(this));
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _asyncSwapper,
        address _claimAddress,
        IERC20 _claimToken
    ) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(_asyncSwapper, "_asyncSwapper");
        Errors.verifyNotZero(_claimAddress, "_claimAddress");
        Errors.verifyNotZero(address(_claimToken), "_claimToken");

        asyncSwapper = _asyncSwapper;
        claimAddress = _claimAddress;
        claimToken = _claimToken;
        weth = systemRegistry.weth();
    }

    function execute(
        bytes calldata data
    ) external onlyDestinationVault nonReentrant {
        EtherFiDVExtensionParams memory params = abi.decode(data, (EtherFiDVExtensionParams));

        uint256 expectedClaimAmount = params.expectedClaimAmount;
        Errors.verifyNotZero(expectedClaimAmount, "expectedClaimAmount");

        EtherFiClaimParams memory claimParams = params.claimParams;
        SwapParams memory swapParams = params.swapParams;

        //
        // Claim rewards
        //
        uint256 claimTokenBalanceBefore = claimToken.balanceOf(address(this));
        ICumulativeMerkleDrop(claimAddress).claim(
            claimParams.account, claimParams.cumulativeAmount, claimParams.expectedMerkleRoot, claimParams.merkleProof
        );

        uint256 claimTokenBalanceAfter = claimToken.balanceOf(address(this));
        uint256 actualClaimAmount = claimTokenBalanceAfter - claimTokenBalanceBefore;
        // Amounts should be exact.  If something is going wrong offchain or with claim contract, this will catch it
        if (actualClaimAmount != expectedClaimAmount) {
            revert InvalidAmountReceived(actualClaimAmount, expectedClaimAmount);
        }

        //
        // Swap for reward token
        //

        // Validations on swapData, amount returned, etc are being done in the `BaseAsyncSwapper` level
        bytes memory swapData = asyncSwapper.functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, swapParams));
        uint256 amountReceived = abi.decode(swapData, (uint256));

        //
        // Add rewards to DV rewarder
        //
        address rewarder = IDestinationVault(address(this)).rewarder();
        LibAdapter._approve(weth, rewarder, amountReceived);
        IMainRewarder(rewarder).queueNewRewards(amountReceived);

        emit EtherFiExtensionExecuted(actualClaimAmount, amountReceived);
    }
}
