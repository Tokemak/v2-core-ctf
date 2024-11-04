// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Systems, Constants } from "../utils/Constants.sol";
import { DestinationIncentiveChecker } from "src/utils/DestinationIncentiveChecker.sol";

contract IncentiveMonitoringDeploy is Script {
    function run() external {
        Constants.Values memory constants = Constants.get(Systems.LST_ETH_MAINNET_GEN3);

        vm.startBroadcast();

        DestinationIncentiveChecker oracle = new DestinationIncentiveChecker(constants.sys.systemRegistry);

        console.log("DestinationIncentiveChecker: ", address(oracle));

        vm.stopBroadcast();
    }
}
