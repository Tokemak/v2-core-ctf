// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseClaimingDestinationVaultExtension } from
    "src/vault/extensions/base/BaseClaimingDestinationVaultExtension.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

import { IMerkleDistributor } from "src/interfaces/external/kelpdao/IMerkleDistributor.sol";

/// @title Destination vault extension for claiming KelpDao rewards
contract KelpDaoClaimingDestinationVaultExtension is BaseClaimingDestinationVaultExtension {
    address public immutable claimContract;
    IERC20 public immutable claimToken;

    /// @param account Account that can claim rewards
    /// @param cumulativeAmount Cumulative amount of rewards for account. Used in Merkle calculations
    /// @param expectedClaimAmount The amount expected to be claimed on this claim
    /// @param index The index of the claim
    /// @param merkleProof Merkle proof used in verification of claim
    struct KelpDaoClaimParams {
        address account;
        uint256 cumulativeAmount;
        uint256 expectedClaimAmount;
        uint256 index;
        bytes32[] merkleProof;
    }

    // slither-disable-start similar-names
    constructor(
        ISystemRegistry _systemRegistry,
        address _asyncSwapper,
        address _claimContract,
        address _claimToken
    ) BaseClaimingDestinationVaultExtension(_systemRegistry, _asyncSwapper) {
        Errors.verifyNotZero(_claimContract, "_claimContract");
        Errors.verifyNotZero(_claimToken, "_claimToken");

        // slither-disable-next-line missing-zero-check
        claimContract = _claimContract;
        claimToken = IERC20(_claimToken);
    }
    // slither-disable-end similar-names

    /// @inheritdoc BaseClaimingDestinationVaultExtension
    function _claim(
        bytes memory data
    ) internal override returns (uint256[] memory amountsClaimed, address[] memory tokensClaimed) {
        KelpDaoClaimParams memory params = abi.decode(data, (KelpDaoClaimParams));
        uint256 expectedClaimAmount = params.expectedClaimAmount;

        Errors.verifyNotZero(expectedClaimAmount, "expectedClaimAmount");

        uint256 claimTokenBalanceBefore = claimToken.balanceOf(address(this));
        IMerkleDistributor(claimContract).claim(
            params.index, params.account, params.cumulativeAmount, params.merkleProof
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
