// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IBaseReward } from "./IBaseReward.sol";

interface IExtraReward is IBaseReward {
    /**
     * @notice Withdraws the specified amount of tokens from the vault for the specified account.
     * @param account The address of the account to withdraw tokens for.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address account, uint256 amount) external;

    /**
     * @notice Claims and transfers all rewards for the specified account from this contract.
     * @param account The address of the account to claim rewards for.
     */
    function getReward(address account) external;
}
