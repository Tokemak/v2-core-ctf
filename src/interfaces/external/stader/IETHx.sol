// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IStaderConfig } from "src/interfaces/external/stader/IStaderConfig.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IETHx is IERC20Metadata {
    function staderConfig() external view returns (IStaderConfig);
}
