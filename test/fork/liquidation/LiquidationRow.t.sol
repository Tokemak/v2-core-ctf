// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-states-count,max-line-length */

import { Test } from "forge-std/Test.sol";

import { AsyncSwapperRegistry } from "src/liquidation/AsyncSwapperRegistry.sol";
import { BaseAsyncSwapper } from "src/liquidation/BaseAsyncSwapper.sol";
import { Roles } from "src/libs/Roles.sol";
import { LiquidationRow } from "src/liquidation/LiquidationRow.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { ILiquidationRow } from "src/interfaces/liquidation/ILiquidationRow.sol";
import { SwapParams } from "src/interfaces/liquidation/IAsyncSwapper.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";

contract LiquidationRowTest is Test {
    address public constant V2_DEPLOYER = 0xA6364F394616DD9238B284CfF97Cd7146C57808D;
    address public constant SYSTEM_REGISTRY = 0x0406d2D96871f798fcf54d5969F69F55F803eEA4;
    address public constant ZERO_EX_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    SystemRegistry internal _systemRegistry;
    AccessController internal _accessController;
    LiquidationRow internal _liquidationRow;

    address internal _asyncSwapper;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_384_915);
        vm.selectFork(forkId);

        vm.startPrank(V2_DEPLOYER);

        _systemRegistry = SystemRegistry(SYSTEM_REGISTRY);
        _accessController = AccessController(address(_systemRegistry.accessController()));

        AsyncSwapperRegistry asyncSwapperRegistry = new AsyncSwapperRegistry(_systemRegistry);
        _systemRegistry.setAsyncSwapperRegistry(address(asyncSwapperRegistry));

        _accessController.grantRole(Roles.AUTO_POOL_REGISTRY_UPDATER, V2_DEPLOYER);
        BaseAsyncSwapper zeroExSwapper = new BaseAsyncSwapper(ZERO_EX_PROXY);
        asyncSwapperRegistry.register(address(zeroExSwapper));
        _asyncSwapper = address(zeroExSwapper);

        _liquidationRow = new LiquidationRow(_systemRegistry);

        _accessController.grantRole(Roles.LIQUIDATOR_MANAGER, address(_liquidationRow));
        _accessController.grantRole(Roles.REWARD_LIQUIDATION_MANAGER, V2_DEPLOYER);
        _accessController.grantRole(Roles.REWARD_LIQUIDATION_EXECUTOR, V2_DEPLOYER);

        _liquidationRow.addToWhitelist(address(zeroExSwapper));

        vm.stopPrank();
    }

    function test_InitialClaimAndLiquidate() public {
        vm.warp(1_709_834_101);
        vm.startPrank(V2_DEPLOYER);

        IDestinationVault[] memory destinationVaults = new IDestinationVault[](2);
        destinationVaults[0] = IDestinationVault(0x73Ab5bf2C7d867F8fb4C4A17fba2A6272873f862);
        destinationVaults[1] = IDestinationVault(0x258Ef53417F3ce45A993b8aD777b87712322Cc7B);
        _liquidationRow.claimsVaultRewards(destinationVaults);

        IDestinationVault[] memory l1Dvs = new IDestinationVault[](1);
        l1Dvs[0] = IDestinationVault(0x73Ab5bf2C7d867F8fb4C4A17fba2A6272873f862);

        ILiquidationRow.LiquidationParams[] memory params = new ILiquidationRow.LiquidationParams[](3);
        params[0] = ILiquidationRow.LiquidationParams({
            fromToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            asyncSwapper: _asyncSwapper,
            vaultsToLiquidate: l1Dvs,
            param: SwapParams({
                sellTokenAddress: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                sellAmount: 272_865_678_297_737,
                buyTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                buyAmount: 314_662_698_445_220,
                //solhint-disable-next-line max-line-length
                data: hex"415565b00000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000f82b7dd38a8900000000000000000000000000000000000000000000000000011b5165d996f300000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000002100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000000000f82b7dd38a89000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000002537573686953776170000000000000000000000000000000000000000000000000000000000000000000f82b7dd38a8900000000000000000000000000000000000000000000000000011bbe5afa7a34000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000006cf520e341000000000000000000000000ad01c20d5886137e056775af56915de824c8fce5000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000084f6b9d93cee2a6599c4df3cad69baaa",
                extraData: abi.encode(""),
                deadline: block.timestamp
            })
        });
        params[1] = ILiquidationRow.LiquidationParams({
            fromToken: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            asyncSwapper: _asyncSwapper,
            vaultsToLiquidate: l1Dvs,
            param: SwapParams({
                sellTokenAddress: 0xD533a949740bb3306d119CC777fa900bA034cd52,
                sellAmount: 18_421_402_276_034_435,
                buyTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                buyAmount: 3_791_099_924_546,
                //solhint-disable-next-line max-line-length
                data: hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000041722af2ed778300000000000000000000000000000000000000000000000000000369db7e1f7400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000d533a949740bb3306d119cc777fa900ba034cd52000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000005eaf3e0be64e15d9298c45bdf398f7de",
                extraData: abi.encode(""),
                deadline: block.timestamp
            })
        });
        params[2] = ILiquidationRow.LiquidationParams({
            fromToken: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
            asyncSwapper: _asyncSwapper,
            vaultsToLiquidate: l1Dvs,
            param: SwapParams({
                sellTokenAddress: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
                sellAmount: 110_528_413_656_206,
                buyTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                buyAmount: 150_914_894_029,
                //solhint-disable-next-line max-line-length
                data: hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000648666d5648e00000000000000000000000000000000000000000000000000000022c946bfc0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000bbdbad099b5f25f74123de89f00db927",
                extraData: abi.encode(""),
                deadline: block.timestamp
            })
        });

        assertEq(IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(l1Dvs[0].rewarder()), 0, "beforeWethBal");

        // Add a 2% price margin
        _liquidationRow.setPriceMarginBps(200);

        _liquidationRow.liquidateVaultsForTokens(params);

        assertEq(
            IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(l1Dvs[0].rewarder()),
            318_604_713_263_795,
            "afterWethBal"
        );
    }
}
