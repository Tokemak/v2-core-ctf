// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//solhint-disable func-name-mixedcase

interface ICurveTokenV5 {
    function set_minter(
        address newMinter
    ) external;
}
