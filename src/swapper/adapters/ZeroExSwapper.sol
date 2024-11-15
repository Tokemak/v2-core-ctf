// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract ZeroExSwapper {
    using SafeERC20 for IERC20;

    struct ZeroExSwapData {
        address approvalTarget;
        address swapTarget;
        address tokenRecipient;
        address fromToken;
        address toToken;
        bytes swapCallData;
    }

    error SwapFailed();

    function swap(
        ZeroExSwapData memory zeroExSwapData
    ) external {
        LibAdapter._approve(IERC20(zeroExSwapData.fromToken), zeroExSwapData.approvalTarget, type(uint256).max);

        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = zeroExSwapData.swapTarget.call(zeroExSwapData.swapCallData);
        // slither-disable-end low-level-calls

        if (!success) {
            revert SwapFailed();
        }

        // return funds
        if (IERC20(zeroExSwapData.toToken).balanceOf(address(this)) > 0) {
            IERC20(zeroExSwapData.toToken).safeTransfer(
                zeroExSwapData.tokenRecipient, IERC20(zeroExSwapData.toToken).balanceOf(address(this))
            );
        }
        LibAdapter._approve(IERC20(zeroExSwapData.fromToken), zeroExSwapData.approvalTarget, 0);
    }
}
