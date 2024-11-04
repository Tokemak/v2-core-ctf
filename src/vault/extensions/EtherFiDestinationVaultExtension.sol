// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseDestinationVaultExtension } from "src/vault/extensions/base/BaseDestinationVaultExtension.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

import { ICumulativeMerkleDrop } from "src/interfaces/external/etherfi/ICumulativeMerkleDrop.sol";

/// @title Destination vault extension for claiming EtherFi rewards
contract EtherFiDestinationVaultExtension is BaseDestinationVaultExtension {
    address public immutable claimContract;
    IERC20 public immutable claimToken;

    /// @param account The account that haas accrued rewards.  DV in this context
    /// @param cumulativeAmount Total amount of rewards accrued. Used in Merkle verifications
    /// @param expectedClaimAmount Amount we expect to claim this time.  Used for validation on our end
    /// @param expectedMerkleRoot The expected merkle root for this claim period
    /// @param merkleProof Merkle proof, used for verification of claim
    struct EtherFiClaimParams {
        address account;
        uint256 cumulativeAmount;
        uint256 expectedClaimAmount;
        bytes32 expectedMerkleRoot;
        bytes32[] merkleProof;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _asyncSwapper,
        address _claimContract,
        address _claimToken
    ) BaseDestinationVaultExtension(_systemRegistry, _asyncSwapper) {
        Errors.verifyNotZero(_claimContract, "_claimContract");
        Errors.verifyNotZero(_claimToken, "_claimToken");

        // slither-disable-next-line missing-zero-check
        claimContract = _claimContract;
        claimToken = IERC20(_claimToken);
    }

    /// @inheritdoc BaseDestinationVaultExtension
    function _claim(
        bytes memory data
    ) internal override returns (uint256[] memory amountsClaimed, address[] memory tokensClaimed) {
        EtherFiClaimParams memory params = abi.decode(data, (EtherFiClaimParams));
        uint256 expectedClaimAmount = params.expectedClaimAmount;

        Errors.verifyNotZero(expectedClaimAmount, "expectedClaimAmount");

        uint256 claimTokenBalanceBefore = claimToken.balanceOf(address(this));
        ICumulativeMerkleDrop(claimContract).claim(
            params.account, params.cumulativeAmount, params.expectedMerkleRoot, params.merkleProof
        );

        amountsClaimed = new uint256[](1);
        tokensClaimed = new address[](1);

        amountsClaimed[0] = claimToken.balanceOf(address(this)) - claimTokenBalanceBefore;
        tokensClaimed[0] = address(claimToken);

        // Amounts should be exact, amount we will be claiming determined before call offchain
        if (amountsClaimed[0] != expectedClaimAmount) {
            revert InvalidAmountReceived(amountsClaimed[0], expectedClaimAmount);
        }
    }
}
