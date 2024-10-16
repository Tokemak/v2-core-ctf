// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Roles } from "src/libs/Roles.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { Client } from "src/external/chainlink/ccip/Client.sol";
import { IRouterClient } from "src/interfaces/external/chainlink/IRouterClient.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SystemRegistryMocks } from "test/unit/mocks/SystemRegistryMocks.t.sol";
import { AccessControllerMocks } from "test/unit/mocks/AccessControllerMocks.t.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { ReceivingRouter } from "src/receivingRouter/ReceivingRouter.sol";
import { CrossChainMessagingUtilities as CCUtils } from "src/libs/CrossChainMessagingUtilities.sol";
import { MessageReceiverBase } from "src/receivingRouter/MessageReceiverBase.sol";
import { Errors } from "src/utils/Errors.sol";

// solhint-disable func-name-mixedcase,contract-name-camelcase

contract ReceivingRouterTests is Test, SystemRegistryMocks, AccessControllerMocks {
    ISystemRegistry internal _systemRegistry;
    IAccessController internal _accessController;
    IRouterClient internal _routerClient;

    ReceivingRouter internal _router;

    error InvalidRouter(address messageSender);

    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);
    event MessageReceiverAdded(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address receiverToAdd
    );
    event MessageReceiverDeleted(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToRemove
    );
    event MessageVersionMismatch(uint256 sourceVersion, uint256 receiverVersion);
    event MessageData(
        uint256 messageTimestamp,
        address messageOrigin,
        bytes32 messageType,
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        bytes message
    );
    event MessageReceived(address messageReceiver, bytes message);

    constructor() SystemRegistryMocks(vm) AccessControllerMocks(vm) { }

    function setUp() public {
        _systemRegistry = ISystemRegistry(makeAddr("systemRegistry"));
        _accessController = IAccessController(makeAddr("accessController"));
        _routerClient = IRouterClient(makeAddr("routerClient"));

        _mockSysRegAccessController(_systemRegistry, address(_accessController));
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));

        _router = new ReceivingRouter(address(_routerClient), _systemRegistry);
    }

    function test_SetUpState() public {
        assertEq(_router.getSystemRegistry(), address(_systemRegistry));
        assertEq(_router.getRouter(), address(_routerClient));
    }

    function _mockRouterIsChainSupported(uint64 chainId, bool supported) internal {
        vm.mockCall(
            address(_routerClient),
            abi.encodeWithSelector(IRouterClient.isChainSupported.selector, chainId),
            abi.encode(supported)
        );
    }

    function _mockIsRouterManager(address user, bool isAdmin) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.RECEIVING_ROUTER_MANAGER, isAdmin);
    }

    function _mockIsRouterExecutor(address user, bool isExecutor) internal {
        _mockAccessControllerHasRole(_accessController, user, Roles.RECEIVING_ROUTER_EXECUTOR, isExecutor);
    }

    function _getMessageReceiversKey(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(messageOrigin, sourceChainSelector, messageType));
    }

    function _buildChainlinkCCIPMessage(
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        address sender,
        bytes memory data
    ) internal pure returns (Client.Any2EVMMessage memory ccipMessageRecevied) {
        Client.EVMTokenAmount[] memory tokenArr = new Client.EVMTokenAmount[](0);
        ccipMessageRecevied = Client.Any2EVMMessage({
            messageId: ccipMessageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(sender),
            data: data,
            destTokenAmounts: tokenArr
        });
    }
}

contract SetSourceChainSendersTest is ReceivingRouterTests {
    function test_SetsSender() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender, 0);
        address[] memory senders = _router.getSourceChainSenders(chainId);
        assertEq(senders[0], sender);
        assertEq(senders[1], address(0));
    }

    function test_EmitsEvent() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectEmit(true, true, true, true);
        emit SourceChainSenderSet(chainId, sender);
        _router.setSourceChainSenders(chainId, sender, 0);
    }

    function test_AllowsZeroAddressReceiverToBeSet() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender, 0);
        assertEq(_router.sourceChainSenders(chainId, 0), sender, "senderIdx1");
        assertEq(_router.sourceChainSenders(chainId, 1), address(0), "senderIdx2");

        _router.setSourceChainSenders(chainId, address(0), 0);
        assertEq(_router.sourceChainSenders(chainId, 0), address(0), "senderIdx1");
        assertEq(_router.sourceChainSenders(chainId, 1), address(0), "senderIdx2");
    }

    function test_AllowsSetAtBothIdxs() public {
        uint64 chainId = 12;
        address sender1 = address(1);
        address sender2 = address(2);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender1, 0);
        assertEq(_router.sourceChainSenders(chainId, 0), sender1, "sender1");
        assertEq(_router.sourceChainSenders(chainId, 1), address(0), "sender2");

        _router.setSourceChainSenders(chainId, sender2, 1);
        assertEq(_router.sourceChainSenders(chainId, 0), sender1, "sender1");
        assertEq(_router.sourceChainSenders(chainId, 1), sender2, "sender2");
    }

    function test_RevertIf_ChainIsNotSupported() public {
        uint64 chainId = 12;
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, false);

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _router.setSourceChainSenders(chainId, address(1), 0);
    }

    function test_RevertIf_DuplicateSender_OtherIdx() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender, 0);

        vm.expectRevert(Errors.ItemExists.selector);
        _router.setSourceChainSenders(chainId, sender, 1);
    }

    function test_RevertIf_DuplicateSender_SameIdx() public {
        uint64 chainId = 12;
        address sender = address(1);
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);

        _router.setSourceChainSenders(chainId, sender, 0);

        vm.expectRevert(Errors.ItemExists.selector);
        _router.setSourceChainSenders(chainId, sender, 0);
    }

    function test_RevertIf_InvalidIdx() public {
        uint64 chainId = 12;
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "idx"));
        _router.setSourceChainSenders(chainId, address(1), 2);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        uint64 chainId = 12;
        _mockIsRouterManager(address(this), false);
        _mockRouterIsChainSupported(chainId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.setSourceChainSenders(chainId, address(1), 0);
    }
}

contract SetMessageReceiversTest is ReceivingRouterTests {
    function test_SavesSingleReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 1, "len");
        assertEq(newValues[0], receiver1, "receiver");
    }

    function test_PassesMultipleSourceChainSendersSet() public {
        _mockIsRouterManager(address(this), true);

        address sender1 = makeAddr("sender1");
        address sender2 = makeAddr("sender2");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender1, 0);
        _router.setSourceChainSenders(chainId, sender2, 1);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender1, messageType, chainId, receivers);

        address[] memory newValues = _router.getMessageReceivers(sender1, chainId, messageType);
        assertEq(newValues.length, 1, "len");
        assertEq(newValues[0], receiver1, "receiver");
    }

    function test_SavesMultipleReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](2);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 2, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_AppendsReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receivers2 = new address[](2);
        receivers2[0] = receiver2;
        receivers2[1] = receiver3;
        _router.setMessageReceivers(sender, messageType, chainId, receivers2);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 3, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
        assertEq(newValues[2], receiver3, "receiver3");
    }

    function test_EmitsEvent() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver;

        vm.expectEmit(true, true, true, true);
        emit MessageReceiverAdded(sender, chainId, messageType, receiver);
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_ReceiverZeroAddress() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "receiverToAdd"));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGiven() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGivenInTheSameCall() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](2);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver1;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_DuplicateReceiverGivenInTheSameCallWithMultiple() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver1;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemExists.selector));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_SourceChainSenderNotSet() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, false);
        receivers[0] = receiver1;

        assertEq(_router.sourceChainSenders(chainId, 0), address(0));
        assertEq(_router.sourceChainSenders(chainId, 1), address(0));

        vm.expectRevert(abi.encodeWithSelector(CCUtils.ChainNotSupported.selector, chainId));
        _router.setMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "messageOrigin"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        bytes32 messageType = 0;
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageType"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_NoRoutes() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageReceiversToSetLength"));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.setMessageReceivers(sender, messageType, 0, receivers);
    }
}

contract RemoveMessageReceiversTest is ReceivingRouterTests {
    function test_CanRemoveOnlyReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver1;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);
        assertEq(newValues.length, 0, "len");
    }

    function test_CanRemoveSingleReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver2;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues.length, 2, "len");
        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver3, "receiver3");
    }

    function test_EmitsEvent() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](2);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver2;

        vm.expectEmit(true, true, true, true);
        emit MessageReceiverDeleted(sender, chainId, messageType, receiver1);
        emit MessageReceiverDeleted(sender, chainId, messageType, receiver2);
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);
    }

    function test_CanRemoveFirstReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver1;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver3, "receiver3");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_CanRemoveLastReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver1, "receiver1");
        assertEq(newValues[1], receiver2, "receiver2");
    }

    function test_CanRemoveFirstAndLastReceiver() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](2);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues[0], receiver2, "receiver2");
    }

    function test_CanRemoveAllReceivers() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        address receiver3 = makeAddr("receiver3");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](3);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        receivers[2] = receiver3;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](3);
        receiversToRemove[0] = receiver1;
        receiversToRemove[1] = receiver2;
        receiversToRemove[2] = receiver3;
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);

        address[] memory newValues = _router.getMessageReceivers(sender, chainId, messageType);

        assertEq(newValues.length, 0, "len");
    }

    function test_RevertIf_NoReceiversConfigured() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        bytes32 messageType = keccak256("message");

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _router.removeMessageReceivers(sender, messageType, 0, receiversToRemove);
    }

    function test_RevertIf_ReceiverNotFound() public {
        _mockIsRouterManager(address(this), true);

        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);

        uint64 chainId = 12;
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);
        receivers[0] = receiver1;

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        address[] memory receiversToRemove = new address[](1);
        receiversToRemove[0] = receiver2;

        vm.expectRevert(abi.encodeWithSelector(Errors.ItemNotFound.selector));
        _router.removeMessageReceivers(sender, messageType, chainId, receiversToRemove);
    }

    function test_RevertIf_EmptySender() public {
        address sender = address(0);
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertIf_EmptyMessageType() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = 0;
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertsIf_EmptySourceChainSelector() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockIsRouterManager(address(this), true);

        vm.expectRevert(Errors.ItemNotFound.selector);
        _router.removeMessageReceivers(sender, messageType, 0, receivers);
    }

    function test_RevertsIf_EmptyReceiver() public {
        address sender = makeAddr("sender");
        address receiver1 = makeAddr("receiver1");
        address zeroReceiver = address(0);
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        uint64 chainId = 12;
        _mockIsRouterManager(address(this), true);
        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);

        _router.setMessageReceivers(sender, messageType, chainId, receivers);

        receivers[0] = zeroReceiver;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "receiverToRemove"));
        _router.removeMessageReceivers(sender, messageType, chainId, receivers);
    }

    function test_RevertIf_CallerIsNotAdmin() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }

    function test_RevertIf_NoRoutesSent() public {
        address sender = makeAddr("sender");
        bytes32 messageType = keccak256("message");
        address[] memory receivers = new address[](0);
        _mockIsRouterManager(address(this), true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector, "messageReceiversToRemoveLength"));
        _router.removeMessageReceivers(sender, messageType, 1, receivers);
    }
}

contract _ccipReceiverTests is ReceivingRouterTests {
    function test_SendToSingleMessageRecevier() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, 0, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender, 0);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.expectEmit(true, true, true, true);
        emit MessageData(0, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver1, message);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_SendToMultipleMessageReceivers() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        address receiver2 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, 0, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender, 0);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.expectEmit(true, true, true, true);
        emit MessageData(0, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver1, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver2, message);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_SuccessfulSend_TwoSourceSendersSet() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, 0, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender, 0);
        _router.setSourceChainSenders(chainId, makeAddr("sender2"), 1);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        vm.expectEmit(true, true, true, true);
        emit MessageData(0, origin, messageType, messageId, chainId, message);
        vm.expectEmit(true, true, true, true);
        emit MessageReceived(receiver1, message);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_SendsFailureEvent_WhenFailureAtMessageReceiver() public {
        _mockIsRouterManager(address(this), true);

        address receiver1 = address(new MockMessageReceiver(_systemRegistry));
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, 0, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver1;

        _mockRouterIsChainSupported(chainId, true);
        _mockSysRegReceivingRouter(_systemRegistry, address(_router));
        _router.setSourceChainSenders(chainId, sender, 0);
        _router.setMessageReceivers(origin, messageType, chainId, receivers);

        MockMessageReceiver(receiver1).setFailure(true);

        vm.expectEmit(true, true, true, true);
        emit MessageData(0, origin, messageType, messageId, chainId, message);

        vm.prank(address(_routerClient));
        vm.expectRevert(MockMessageReceiver.Fail.selector);
        _router.ccipReceive(ccipMessage);
    }

    function test_RevertIf_NoMessageReceiversRegistered() external {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = CCUtils.encodeMessage(origin, 0, messageType, message);

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);

        vm.expectRevert(
            abi.encodeWithSelector(ReceivingRouter.NoMessageReceiversRegistered.selector, origin, messageType, chainId)
        );
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_EmitsFailureEvent_VersionMismatch() public {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;

        address origin = makeAddr("origin");
        uint256 messageVersionSource = 2;
        uint256 messageVersionReceiver = CCUtils.getVersion();
        bytes32 messageType = keccak256("messageType");
        bytes memory message = abi.encode("message");
        bytes memory data = abi.encode(
            CCUtils.Message({
                messageOrigin: origin,
                version: messageVersionSource,
                messageNonce: 0,
                messageType: messageType,
                message: message
            })
        );

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, sender, 0);

        vm.expectEmit(true, true, true, true);
        emit MessageVersionMismatch(messageVersionSource, messageVersionReceiver);
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_RevertIf_SourceChainSenderNotSet() public {
        _mockIsRouterManager(address(this), true);

        bytes32 messageId = keccak256("messageId");
        address senderSourceChain = makeAddr("senderSourceChain");
        address senderSetReceivingChain = makeAddr("senderSetReceivingChain");
        uint64 chainId = 12;
        bytes memory data = abi.encode("data");

        Client.Any2EVMMessage memory ccipMessage =
            _buildChainlinkCCIPMessage(messageId, chainId, senderSourceChain, data);

        _mockRouterIsChainSupported(chainId, true);
        _router.setSourceChainSenders(chainId, senderSetReceivingChain, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ReceivingRouter.InvalidSenderFromSource.selector,
                chainId,
                senderSourceChain,
                senderSetReceivingChain,
                address(0)
            )
        );
        vm.prank(address(_routerClient));
        _router.ccipReceive(ccipMessage);
    }

    function test_RevertIf_NotRouterCall() public {
        bytes32 messageId = keccak256("messageId");
        address sender = makeAddr("sender");
        uint64 chainId = 12;
        bytes memory data = abi.encode("data");

        Client.Any2EVMMessage memory ccipMessage = _buildChainlinkCCIPMessage(messageId, chainId, sender, data);

        vm.expectRevert(abi.encodeWithSelector(InvalidRouter.selector, address(this)));
        _router.ccipReceive(ccipMessage);
    }
}

contract MockMessageReceiver is MessageReceiverBase, SystemComponent {
    bool public receiveFail = false;

    error Fail();

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) { }

    function _onMessageReceive(bytes32, uint256, bytes memory) internal view override {
        if (receiveFail) revert Fail();
    }

    function setFailure(
        bool toSet
    ) external {
        receiveFail = toSet;
    }
}
