// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolData } from "src/external/balancer/VaultTypes.sol";

// TODO: Should break structs out into VaultTypes like in Bal
// TODO: PoolConfigBits? Look at this closer

interface IVaultV3 {
    /**
     * @notice Returns comprehensive pool data for the given pool.
     * @dev This contains the pool configuration (flags), tokens and token types, rates, scaling factors, and balances.
     * @param pool The address of the pool
     * @return poolData The `PoolData` result
     */
    function getPoolData(
        address pool
    ) external view returns (PoolData memory);
}
