// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IStaderConfig } from "src/interfaces/external/stader/IStaderConfig.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Pieces of the real IStaderOracle
interface IStaderOracle {
    /// @title ExchangeRate
    /// @notice This struct holds data related to the exchange rate between ETH and ETHX.
    struct ExchangeRate {
        /// @notice The block number when the exchange rate was last updated.
        uint256 reportingBlockNumber;
        /// @notice The total balance of Ether (ETH) in the system.
        uint256 totalETHBalance;
        /// @notice The total supply of the liquid staking token (ETHX) in the system.
        uint256 totalETHXSupply;
    }

    function getExchangeRate() external view returns (ExchangeRate memory);
}
