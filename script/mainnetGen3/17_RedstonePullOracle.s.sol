// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { CustomRedStoneOracleAdapter } from "src/oracles/providers/CustomRedStoneOracleAdapter.sol";

contract RedstonePullOracle is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        // Set default authorized signers from PrimaryProdDataServiceConsumerBase
        address[] memory defaultAuthorizedSigners = new address[](5);
        defaultAuthorizedSigners[0] = 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774;
        defaultAuthorizedSigners[1] = 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499;
        defaultAuthorizedSigners[2] = 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202;
        defaultAuthorizedSigners[3] = 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE;
        defaultAuthorizedSigners[4] = 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de;

        CustomRedStoneOracleAdapter oracle = new CustomRedStoneOracleAdapter(
            constants.sys.systemRegistry, address(constants.sys.subOracles.customSet), 3, defaultAuthorizedSigners
        );

        console.log("CustomRedStoneOracleAdapter: ", address(oracle));

        vm.stopBroadcast();
    }
}
