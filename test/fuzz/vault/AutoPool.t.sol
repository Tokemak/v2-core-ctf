// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase,max-states-count

import { ERC4626Test } from "test/fuzz/vault/ERC4626Test.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { AutopoolETH } from "src/vault/AutopoolETH.sol";
import { Roles } from "src/libs/Roles.sol";
import { AutopoolETHStrategyTestHelpers as stratHelpers } from "test/strategy/AutopoolETHStrategyTestHelpers.sol";
import { AutopoolETHStrategy } from "src/strategy/AutopoolETHStrategy.sol";

contract AutopoolETHTest is ERC4626Test, BaseTest {
    address private autoPoolStrategy = vm.addr(10_001);

    function setUp() public override(BaseTest, ERC4626Test) {
        vm.warp(1000 days);

        // everything's mocked, so disable forking
        super._setUp(false);

        _underlying_ = address(baseAsset);

        // create vault
        bytes memory initData = abi.encode("");

        AutopoolETHStrategy stratTemplate = new AutopoolETHStrategy(systemRegistry, stratHelpers.getDefaultConfig());
        systemRegistry.accessController().grantRole(Roles.AUTO_POOL_FACTORY_MANAGER, address(this));
        autoPoolFactory.addStrategyTemplate(address(stratTemplate));

        AutopoolETH vault = AutopoolETH(
            autoPoolFactory.createVault{ value: WETH_INIT_DEPOSIT }(
                address(stratTemplate), "x", "y", keccak256("v8"), initData
            )
        );

        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;
    }

    function test_redeem_Setup() public virtual {
        address[4] memory user = [address(1), address(2), address(3), address(4)];
        uint256[4] memory sharesAr = [uint256(1e18), 1e18, 1e18, 1e18];
        uint256[4] memory asset = [uint256(1e18), 1e18, 1e18, 1e18];
        uint256 shares = 1e18;
        uint256 allowance = 1e18;

        Init memory init = Init({ user: user, share: sharesAr, asset: asset, yield: 4 });

        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        shares = bound(shares, 0, _max_redeem(owner));
        _approve(_vault_, owner, caller, allowance);
        prop_redeem(caller, receiver, owner, shares);
    }
}
