// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Lens } from "src/lens/Lens.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { IAutopool } from "src/interfaces/vault/IAutopool.sol";
import { WETH_MAINNET, EZETH_MAINNET } from "test/utils/Addresses.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { AccessController } from "src/security/AccessController.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";

// solhint-disable func-name-mixedcase,max-states-count,state-visibility,max-line-length
// solhint-disable avoid-low-level-calls,gas-custom-errors,custom-errors

contract LensInt is Test {
    address public constant SYSTEM_REGISTRY = 0x2218F90A98b0C070676f249EF44834686dAa4285;
    address public constant SYSTEM_REGISTRY_SEPOLIA = 0x25F603C1a0Ce130c7F25321A7116379d3c270c23;

    Lens internal lens;

    AccessController internal access;

    function _setUp(uint256 _forkId, address _systemRegistry) internal {
        vm.selectFork(_forkId);
        vm.label(_systemRegistry, "systemRegistry");

        ISystemRegistry systemRegistry = ISystemRegistry(_systemRegistry);

        access = AccessController(address(systemRegistry.accessController()));

        lens = new Lens(systemRegistry);
    }

    function _findIndexOfPool(Lens.Autopool[] memory pools, address toFind) internal returns (uint256) {
        uint256 ix = 0;
        bool found = false;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].poolAddress == toFind) {
                ix = i;
                found = true;
                break;
            }
        }

        assertEq(found, true, "poolFound");

        return ix;
    }

    function _findIndexOfDestination(
        Lens.Autopools memory data,
        uint256 autoPoolIx,
        address toFind
    ) internal returns (uint256) {
        uint256 ix = 0;
        bool found = false;
        for (uint256 i = 0; i < data.destinations[autoPoolIx].length; i++) {
            if (data.destinations[autoPoolIx][i].vaultAddress == toFind) {
                ix = i;
                found = true;
                break;
            }
        }

        assertEq(found, true, "vaultFound");

        return ix;
    }
}

contract LensIntTest1 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsVaults() public {
        Lens.Autopool[] memory vaults = lens.getPools();

        assertEq(vaults.length, 3, "len");
        assertEq(vaults[0].poolAddress, 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56, "addr0");
        assertEq(vaults[1].poolAddress, 0x6dC3ce9C57b20131347FDc9089D740DAf6eB34c5, "addr1");
        assertEq(vaults[2].poolAddress, 0xE800e3760FC20aA98c5df6A9816147f190455AF3, "addr2");
    }
}

contract LensIntTest2 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsDestinations() external {
        Lens.Autopools memory retValues = lens.getPoolsAndDestinations();

        assertEq(retValues.autoPools.length, 3, "vaultLen");
        assertEq(retValues.autoPools[2].poolAddress, 0xE800e3760FC20aA98c5df6A9816147f190455AF3, "autoPoolAddr");

        assertEq(retValues.destinations[2].length, 6, "destLen");
        assertEq(
            retValues.destinations[2][0].vaultAddress, 0xC4c973eDC82CB6b972C555672B4e63713C177995, "vault2Dest0Address"
        );
        assertEq(
            retValues.destinations[2][1].vaultAddress, 0x148Ca723BefeA7b021C399413b8b7426A4701500, "vault2Dest1Address"
        );

        assertTrue(retValues.destinations[2][0].statsSafeLPTotalSupply > 0, "vault2Dest0SafeTotalSupply");
        assertTrue(retValues.destinations[2][1].statsSafeLPTotalSupply > 0, "vault2Dest1SafeTotalSupply");

        assertTrue(retValues.destinations[2][0].actualLPTotalSupply > 0, "vault2Dest0ActualTotalSupply");
        assertTrue(retValues.destinations[2][1].actualLPTotalSupply > 0, "vault2Dest1ActualTotalSupply");

        assertEq(retValues.destinations[2][0].exchangeName, "balancer", "vault2Dest0Exchange");
        assertEq(retValues.destinations[2][1].exchangeName, "balancer", "vault2Dest1Exchange");

        assertEq(
            retValues.destinations[2][0].underlyingTokens[0].tokenAddress, EZETH_MAINNET, "v2d0UnderlyingTokens0Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[2][0].underlyingTokenSymbols[0].symbol)),
            keccak256(abi.encode("ezETH")),
            "v2d0UnderlyingTokens0Symbol"
        );
        assertEq(
            retValues.destinations[2][0].underlyingTokens[1].tokenAddress, WETH_MAINNET, "v2d0UnderlyingTokens1Addr"
        );
        assertEq(
            keccak256(abi.encode(retValues.destinations[2][0].underlyingTokenSymbols[1].symbol)),
            keccak256(abi.encode("WETH")),
            "v2d0UnderlyingTokens1Symbol"
        );
    }
}

contract LensIntTest3 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsUpdatedNavPerShare() public {
        // Have deployed the vault 4 time and the vault we're testing has had a debt reporting and claimed
        // rewards so has an increased nav/share

        Lens.Autopool[] memory vaults = lens.getPools();

        assertEq(vaults.length, 3, "len");

        uint256 ix = _findIndexOfPool(vaults, 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56);
        assertEq(vaults[ix].poolAddress, 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56, "addr");
        assertEq(vaults[ix].navPerShare, 1_001_215_424_980_089_616, "navShare");
    }
}

contract LensIntTest4 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsDestinationsWhenPricingIsStale() external {
        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 ix = _findIndexOfPool(data.autoPools, 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56);

        bool someDestStatsIncomplete = false;
        for (uint256 d = 0; d < data.destinations[ix].length; d++) {
            if (data.destinations[ix][d].statsIncomplete) {
                someDestStatsIncomplete = true;
            }
        }

        assertEq(someDestStatsIncomplete, false, "destStatsIncomplete");
    }

    function test_ReturnsDestinationsQueuedForRemoval() external {
        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56);
        uint256 dix = _findIndexOfDestination(data, pix, data.destinations[pix][0].vaultAddress);

        assertEq(data.destinations[pix].length, 13, "destLen");
        assertEq(data.destinations[pix][dix].lpTokenAddress, 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276, "lp");
    }
}

contract LensIntTest5 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_ReturnsVaultData() external {
        address autoPool = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56;
        address admin = 0x123cC4AFA59160C6328C0152cf333343F510e5A3;

        uint256 streamingFee = 2000;
        uint256 periodicFee = 85;

        vm.startPrank(admin);
        access.grantRole(Roles.AUTO_POOL_FEE_UPDATER, admin);
        AutopoolETH(autoPool).setRebalanceFeeHighWaterMarkEnabled(true);
        vm.stopPrank();

        Lens.Autopool[] memory autoPools = lens.getPools();
        Lens.Autopool memory pool = autoPools[_findIndexOfPool(autoPools, autoPool)];

        assertEq(pool.poolAddress, autoPool, "poolAddress");
        assertEq(pool.name, "Tokemak autoETH", "name");
        assertEq(pool.symbol, "autoETH", "symbol");
        assertEq(pool.vaultType, 0xde6f3096d4f66344ff788320cd544f72ff6f5662e94f10e931a2dc34104866b7, "vaultType");
        assertEq(pool.baseAsset, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "baseAsset");
        assertEq(pool.streamingFeeBps, streamingFee, "streamingFeeBps");
        assertEq(pool.periodicFeeBps, periodicFee, "periodicFeeBps");
        assertEq(pool.feeHighMarkEnabled, true, "feeHighMarkEnabled");
        assertEq(pool.feeSettingsIncomplete, false, "feeSettingsIncomplete");
        assertEq(pool.isShutdown, false, "isShutdown");
        assertEq(uint256(pool.shutdownStatus), uint256(IAutopool.VaultShutdownStatus.Active), "shutdownStatus");
        assertEq(pool.rewarder, 0x60882D6f70857606Cdd37729ccCe882015d1755E, "rewarder");
        assertEq(pool.strategy, 0xf5f6addB08c5e6091e5FdEc7326B21bEEd942235, "strategy");
        assertEq(pool.totalSupply, 10_520_464_591_205_808_094_996, "totalSupply");
        assertEq(pool.totalAssets, 10_533_251_426_672_107_925_609, "totalAssets");
        assertEq(pool.totalIdle, 790_879_467_361_623_514_707, "totalIdle");
        assertEq(pool.totalDebt, 9_742_371_959_310_484_410_902, "totalDebt");
        assertEq(pool.navPerShare, 1_001_215_424_980_089_616, "navPerShare");
    }
}

contract LensIntTest6 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_927_387);
        _setUp(forkId, SYSTEM_REGISTRY);
    }

    function test_CompositeReturn() external {
        address autoPool = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56;
        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, autoPool);
        uint256 dix = _findIndexOfDestination(data, pix, data.destinations[pix][0].vaultAddress);
        Lens.DestinationVault memory dv = data.destinations[pix][dix];

        assertTrue(dv.compositeReturn > 0, "compositeReturn");
    }

    function test_ReturnsDestinationVaultData() external {
        address autoPool = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56;

        Lens.Autopools memory data = lens.getPoolsAndDestinations();
        uint256 pix = _findIndexOfPool(data.autoPools, autoPool);
        address destVault = data.destinations[pix][0].vaultAddress;
        address admin = 0x123cC4AFA59160C6328C0152cf333343F510e5A3;

        vm.startPrank(admin);
        access.grantRole(Roles.DESTINATION_VAULT_MANAGER, admin);
        IDestinationVault(destVault).shutdown(IDestinationVault.VaultShutdownStatus.Exploit);
        vm.stopPrank();

        uint256 dix = _findIndexOfDestination(data, pix, destVault);
        Lens.DestinationVault memory dv = data.destinations[pix][dix];

        assertEq(dv.vaultAddress, destVault, "vaultAddress");
        assertEq(dv.exchangeName, "balancer", "exchangeName");
        assertEq(dv.totalSupply, 0, "totalSupply");
        assertEq(dv.lastSnapshotTimestamp, 1_728_404_123, "lastSnapshotTimestamp");
        assertEq(dv.feeApr, 3_566_712_654_967_438, "feeApr");
        assertEq(dv.lastDebtReportTime, 0, "lastDebtReportTime");
        assertEq(dv.minDebtValue, 0, "minDebtValue");
        assertEq(dv.maxDebtValue, 0, "maxDebtValue");
        assertEq(dv.debtValueHeldByVault, 0, "debtValueHeldByVault");
        assertEq(dv.queuedForRemoval, false, "queuedForRemoval");
        assertEq(dv.isShutdown, false, "isShutdown");
        assertEq(uint256(dv.shutdownStatus), uint256(IDestinationVault.VaultShutdownStatus.Active), "shutdownStats");
        assertEq(dv.statsIncomplete, false, "statsIncomplete");
        assertEq(dv.autoPoolOwnsShares, 0, "vaultOwnsShares");
        assertEq(dv.actualLPTotalSupply, 13_157_002_932_698_265_318_461, "actualLPTotalSupply");
        assertEq(dv.dexPool, 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276, "dexPool");
        assertEq(dv.lpTokenAddress, 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276, "lpTokenAddress");
        assertEq(dv.lpTokenSymbol, "B-rETH-STABLE", "lpTokenSymbol");
        assertEq(dv.lpTokenName, "Balancer rETH Stable Pool", "lpTokenName");
        assertEq(dv.statsSafeLPTotalSupply, 12_383_284_544_307_852_558_705, "statsSafeLPTotalSupply");
        assertEq(dv.statsIncentiveCredits, 168, "statsIncentiveCredits");
        assertEq(dv.reservesInEth.length, 2, "reservesInEthLen");
        assertEq(dv.reservesInEth[0], 6_734_889_594_467_612_556_506, "reservesInEth0");
        assertEq(dv.reservesInEth[1], 6_902_574_557_991_798_529_924, "reservesInEth1");
        assertEq(dv.statsPeriodFinishForRewards.length, 4, "statsPeriodFinishForRewardsLen");
        assertEq(dv.statsPeriodFinishForRewards[0], 1_728_868_991, "statsPeriodFinishForRewards[0]");
        assertEq(dv.statsPeriodFinishForRewards[1], 1_728_868_991, "statsPeriodFinishForRewards[1]");
        assertEq(dv.statsAnnualizedRewardAmounts.length, 4, "statsAnnualizedRewardAmountsLen");
        assertEq(dv.statsAnnualizedRewardAmounts[0], 399_754_439_182_344_356_496_000, "statsAnnualizedRewardAmounts[0]");
        assertEq(dv.statsAnnualizedRewardAmounts[1], 420_541_670_019_826_263_033_792, "statsAnnualizedRewardAmounts[1]");
        assertEq(dv.rewardsTokens.length, 4, "rewardTokenAddressLen");
        assertEq(dv.rewardsTokens[0].tokenAddress, 0xba100000625a3754423978a60c9317c58a424e3D, "rewardTokenAddress0");
        assertEq(dv.rewardsTokens[1].tokenAddress, 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF, "rewardTokenAddress1");
        assertEq(dv.rewardsTokens[2].tokenAddress, 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF, "rewardTokenAddress2");
        assertEq(dv.rewardsTokens[3].tokenAddress, 0xD33526068D116cE69F19A9ee46F0bd304F21A51f, "rewardTokenAddress3");
        assertEq(dv.underlyingTokens.length, 2, "underlyingTokenAddressLen");
        assertEq(
            dv.underlyingTokens[0].tokenAddress, 0xae78736Cd615f374D3085123A210448E74Fc6393, "underlyingTokenAddress[0]"
        );
        assertEq(
            dv.underlyingTokens[1].tokenAddress, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "underlyingTokenAddress[1]"
        );
        assertEq(dv.underlyingTokenSymbols.length, 2, "underlyingTokenSymbolsLen");
        assertEq(dv.underlyingTokenSymbols[0].symbol, "rETH", "underlyingTokenSymbols[0]");
        assertEq(dv.underlyingTokenSymbols[1].symbol, "WETH", "underlyingTokenSymbols[1]");
        assertEq(dv.underlyingTokenValueHeld.length, 2, "underlyingTokenValueHeldLen");
        assertEq(dv.underlyingTokenValueHeld[0].valueHeldInEth, 0, "underlyingTokenValueHeld[0]");
        assertEq(dv.underlyingTokenValueHeld[1].valueHeldInEth, 0, "underlyingTokenValueHeld[0]");
        assertEq(dv.lstStatsData.length, 2, "lstStatsDataLen");
        assertEq(dv.lstStatsData[0].lastSnapshotTimestamp, 1_728_412_139, "lstStatsData[0].lastSnapshotTimestamp");
        assertEq(dv.lstStatsData[1].lastSnapshotTimestamp, 0, "lstStatsData[1].lastSnapshotTimestamp");
    }
}

contract LensIntTest7 is LensInt {
    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("SEPOLIA_RPC_URL"), 6_589_364);
        _setUp(forkId, SYSTEM_REGISTRY_SEPOLIA);
    }

    function test_ReturnsAutopoolUserInfo() external {
        {
            Lens.UserAutopoolRewardInfo memory userInfo =
                lens.getUserRewardInfo(0x09618943342c016A85aC0F98Fd005479b3cec571);

            assertEq(userInfo.autopools.length, 2, "userInfoLen");
            assertEq(userInfo.rewardTokens[0].length, 1, "rewardTokensLen");
            assertEq(userInfo.rewardTokenAmounts[0].length, 1, "rewardTokenAmountsLen");
            assertEq(
                userInfo.rewardTokens[0][0].tokenAddress,
                0xEec5970a763C0ae3Eb2a612721bD675DdE2561C2, // TOKE SEPOLIA
                "rewardTokenAddress"
            );
            assertEq(userInfo.rewardTokenAmounts[0][0].amount, 1_197_530_864_197_530_864, "rewardTokenAmount");
        }
    }
}
