// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

contract Numbers {
    /// @notice Tweak the value up or down by the provided pct
    function tweak(uint256 value, int8 pct) internal pure returns (uint256 output) {
        output = value;

        if (pct < 0) {
            output -= output * uint256(int256(pct) * -1) / 128;
        } else if (pct > 0) {
            output += output * uint256(uint8(pct)) / 127;
        }
    }

    /// @notice Tweak the value up or down by the provided pct
    function tweak16(uint256 value, int16 pct) internal pure returns (uint256 output) {
        output = value;

        if (pct < 0) {
            output -= output * uint256(int256(pct) * -1) / 32_768;
        } else if (pct > 0) {
            output += output * uint256(uint16(pct)) / 32_767;
        }
    }

    function scaleTo(uint8 num, uint256 max) internal pure returns (uint256 scaled) {
        if (num == type(uint8).max) {
            return max;
        }
        scaled = (uint256(num) * 100) / (((uint256(type(uint8).max) * 100)) / (max + 1));
    }

    function pctOf(uint256 num, uint8 pct) internal pure returns (uint256 applied) {
        applied = num * ((uint256(pct) * 100) / type(uint8).max) / 100;
    }
}
