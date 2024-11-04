// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase,max-states-count

import { Vm } from "forge-std/Vm.sol";
import { IAutopoolStrategy } from "src/interfaces/strategy/IAutopoolStrategy.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";

contract AutopoolStrategyMocks {
    Vm private vm;

    constructor(
        Vm _vm
    ) {
        vm = _vm;
    }

    function _mockSuccessfulRebalance(
        address strategy
    ) internal {
        _mockVerifyRebalance(strategy, true, "");
        _mockNavUpdate(strategy);
        _mockRebalanceSuccessfullyExecuted(strategy);
        _mockGetRebalanceOutSummaryStats(strategy);
    }

    function _mockFailingRebalance(address strategy, string memory message) internal {
        _mockGetRebalanceOutSummaryStats(strategy);
        _mockVerifyRebalance(strategy, false, message);
    }

    function _mockVerifyRebalance(address strategy, bool success, string memory message) internal {
        vm.mockCall(
            strategy, abi.encodeWithSelector(IAutopoolStrategy.verifyRebalance.selector), abi.encode(success, message)
        );
    }

    function _mockVerifyRebalance(
        address strategy,
        IStrategy.RebalanceParams memory params,
        IStrategy.SummaryStats memory stats,
        bool success,
        string memory message
    ) internal {
        vm.mockCall(
            strategy,
            abi.encodeWithSelector(IAutopoolStrategy.verifyRebalance.selector, params, stats),
            abi.encode(success, message)
        );
    }

    function _mockNavUpdate(
        address strategy
    ) internal {
        vm.mockCall(strategy, abi.encodeWithSelector(IAutopoolStrategy.navUpdate.selector), abi.encode(""));
    }

    function _mockRebalanceSuccessfullyExecuted(
        address strategy
    ) internal {
        vm.mockCall(
            strategy, abi.encodeWithSelector(IAutopoolStrategy.rebalanceSuccessfullyExecuted.selector), abi.encode("")
        );
    }

    function _mockGetRebalanceOutSummaryStats(
        address strategy
    ) internal {
        IStrategy.SummaryStats memory ret;

        vm.mockCall(
            strategy, abi.encodeWithSelector(IAutopoolStrategy.getRebalanceOutSummaryStats.selector), abi.encode(ret)
        );
    }
}
