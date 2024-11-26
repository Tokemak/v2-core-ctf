// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

import { Test } from "forge-std/Test.sol";
import { BAL_VAULT } from "test/utils/Addresses.sol";

import { IBasePool } from "src/interfaces/external/balancer/IBasePool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {
    BalancerV2MetaStableMathOracle,
    BalancerV2BaseStableMathOracle
} from "src/oracles/providers/BalancerV2MetaStableMathOracle.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { Errors } from "src/utils/Errors.sol";

contract BalancerV2MetaStableMathOracleTest is Test {
    address public constant BAL_META_RETH_WETH = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    IVault public constant BAL_VAULT_INSTANCE = IVault(BAL_VAULT);

    ISystemRegistry public registry;
    MockBalancerV2MetaStableMathOracle public oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_223_712);

        registry = ISystemRegistry(makeAddr("registry"));

        // Mock rootPriceOracle call on system registry.  Can be any address not zero
        vm.mockCall(address(registry), abi.encodeCall(ISystemRegistry.rootPriceOracle, ()), abi.encode(address(1)));

        oracle = new MockBalancerV2MetaStableMathOracle(BAL_VAULT_INSTANCE, registry);
    }

    function test_Revert_VaultZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_vault"));
        new MockBalancerV2MetaStableMathOracle(IVault(address(0)), registry);
    }

    function test_SetsStateOnConstruction() public {
        assertEq(address(oracle.getSystemRegistry()), address(registry));
        assertEq(address(oracle.vault()), BAL_VAULT);
    }

    function test_getTotalSupply_RunsProperly() public {
        uint256 supplyFromOracle = oracle.getTotalSupply(BAL_META_RETH_WETH);
        uint256 supplyFromPool = IERC20(BAL_META_RETH_WETH).totalSupply();

        assertEq(supplyFromOracle, supplyFromPool);
    }

    function test_getPoolTokens_RunsProperly() public {
        (IERC20[] memory tokens, uint256[] memory rawBalances) =
            BalancerUtilities._getPoolTokens(BAL_VAULT_INSTANCE, BAL_META_RETH_WETH);
        bytes memory expectedData = abi.encode(
            BalancerV2BaseStableMathOracle.BalancerV2StableOracleData({
                pool: BAL_META_RETH_WETH,
                rawBalances: rawBalances
            })
        );

        (IERC20[] memory tokensFromOracle, uint256[] memory rawBalancesFromPool, bytes memory data) =
            oracle.getPoolTokens(BAL_META_RETH_WETH);

        assertEq(address(tokens[0]), address(tokensFromOracle[0]));
        assertEq(address(tokens[1]), address(tokensFromOracle[1]));
        assertEq(rawBalances[0], rawBalancesFromPool[0]);
        assertEq(rawBalances[1], rawBalancesFromPool[1]);
        assertEq(expectedData, data);
    }

    function test_getScalingFactors_RunsProperly() public {
        uint256[] memory poolScalingFactors = IBasePool(BAL_META_RETH_WETH).getScalingFactors();

        uint256[] memory oracleScalingFactors = oracle.getScalingFactors(BAL_META_RETH_WETH);

        assertEq(poolScalingFactors[0], oracleScalingFactors[0]);
        assertEq(poolScalingFactors[1], oracleScalingFactors[1]);
    }

    function test_getLiveBalancesAndScalingFactors_RunsProperly() public {
        uint256[] memory poolScalingFactors = IBasePool(BAL_META_RETH_WETH).getScalingFactors();
        (, uint256[] memory rawBalances,) = BAL_VAULT_INSTANCE.getPoolTokens(IBasePool(BAL_META_RETH_WETH).getPoolId());

        // Encoding expected data for scaling factors and live balances call
        bytes memory data = abi.encode(
            BalancerV2BaseStableMathOracle.BalancerV2StableOracleData({
                pool: BAL_META_RETH_WETH,
                rawBalances: rawBalances
            })
        );

        uint256[] memory calculatedLiveBalances = new uint256[](2);
        for (uint256 i = 0; i < calculatedLiveBalances.length; ++i) {
            calculatedLiveBalances[i] = poolScalingFactors[i] * rawBalances[i] / 1e18;
        }

        (uint256[] memory oracleLiveBalances, uint256[] memory oracleScalingFactors) =
            oracle.getLiveBalancesAndScalingFactors(data);

        assertEq(oracleLiveBalances[0], calculatedLiveBalances[0]);
        assertEq(oracleLiveBalances[1], calculatedLiveBalances[1]);
        assertEq(poolScalingFactors[0], oracleScalingFactors[0]);
        assertEq(poolScalingFactors[1], oracleScalingFactors[1]);
    }
}

contract MockBalancerV2MetaStableMathOracle is BalancerV2MetaStableMathOracle {
    constructor(IVault _vault, ISystemRegistry _registry) BalancerV2MetaStableMathOracle(_vault, _registry) { }

    function getTotalSupply(
        address pool
    ) external view returns (uint256) {
        return _getTotalSupply(pool);
    }

    function getPoolTokens(
        address pool
    ) external view returns (IERC20[] memory, uint256[] memory, bytes memory) {
        return _getPoolTokens(pool);
    }

    function getScalingFactors(
        address pool
    ) external view returns (uint256[] memory) {
        return _getScalingFactors(pool);
    }

    function getLiveBalancesAndScalingFactors(
        bytes memory data
    ) external view returns (uint256[] memory, uint256[] memory) {
        return _getLiveBalancesAndScalingFactors(data);
    }
}
