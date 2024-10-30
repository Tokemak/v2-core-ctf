// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { BaseDestinationVaultExtension } from "src/vault/extensions/base/BaseDestinationVaultExtension.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Errors } from "src/utils/Errors.sol";

import { IMerkleDistributor } from "src/interfaces/external/kelpdao/IMerkleDistributor.sol";

contract KelpDaoDestinationVaultExtension is BaseDestinationVaultExtension {
    address public immutable claimContract;
    IERC20 public immutable claimToken;

    error InvalidImplementation(address queriedImplementation);

    struct KelpDaoClaimParams {
        address account;
        uint256 cumulativeAmount;
        uint256 expectedClaimAmount;
        uint256 index;
        bytes32[] merkleProof;
    }

    constructor(
        ISystemRegistry _systemRegsitry,
        address _asyncSwapper,
        address _claimContract,
        address _claimToken
    ) BaseDestinationVaultExtension(_systemRegsitry, _asyncSwapper) {
        Errors.verifyNotZero(_claimContract, "_claimContract");
        Errors.verifyNotZero(_claimToken, "_claimToken");

        claimContract = _claimContract;
        claimToken = IERC20(_claimToken);
    }

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

        if (amountsClaimed[0] != expectedClaimAmount) {
            revert InvalidAmountReceived(amountsClaimed[0], expectedClaimAmount);
        }
    }
}
