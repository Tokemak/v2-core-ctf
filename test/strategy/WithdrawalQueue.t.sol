// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { WithdrawalQueue } from "src/strategy/WithdrawalQueue.sol";
import { StructuredLinkedList } from "src/strategy/StructuredLinkedList.sol";

// solhint-disable func-name-mixedcase
contract WithdrawalQueueTest is Test {
    using StructuredLinkedList for StructuredLinkedList.List;

    StructuredLinkedList.List private queue;
    address private constant _NULL = address(0);

    address private constant DESTINATION1 = 0x1111111111111111111111111111111111111111;
    address private constant DESTINATION2 = 0x2222222222222222222222222222222222222222;
    address private constant DESTINATION3 = 0x3333333333333333333333333333333333333333;
    address private constant DESTINATION4 = 0x4444444444444444444444444444444444444444;
    address private constant DESTINATION5 = 0x5555555555555555555555555555555555555555;

    // ##################### BASE CASES ########################

    function test_peek_empty_never_added() public {
        assertEq(WithdrawalQueue.peekHead(queue), _NULL);
        assertEq(WithdrawalQueue.peekTail(queue), _NULL);
    }

    function test_emptyQueue_addressExists_False() public {
        assertEq(WithdrawalQueue.addressExists(queue, DESTINATION1), false);
    }

    function test_addToHead_from_empty() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);
    }

    function test_addToTail_from_empty() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);
    }

    function test_pop_notExistingAddress() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);

        assertFalse(WithdrawalQueue.addressExists(queue, DESTINATION3));
        WithdrawalQueue.popAddress(queue, DESTINATION3);
        assertFalse(WithdrawalQueue.addressExists(queue, DESTINATION3));
    }

    function test_verifyEmptyQueue() public {
        verifyEmptyQueue(queue);
    }

    function test_addToHead_SeveralDuplicates() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);
    }

    function test_addToTail_SeveralDuplicates() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);
    }

    function test_addToHead_and_addToTail_SeveralDuplicates() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);

        WithdrawalQueue.addToTail(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);

        WithdrawalQueue.addToHead(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);

        WithdrawalQueue.addToTail(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);
    }

    function test_addToHead_SeveralNonDuplicates() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);

        WithdrawalQueue.addToHead(queue, DESTINATION2);
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);

        WithdrawalQueue.addToHead(queue, DESTINATION3);
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION3);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);
    }

    // ############################## POP TESTS ########################################

    function test_addToHead_ThenPop() public {
        WithdrawalQueue.addToHead(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);

        WithdrawalQueue.popAddress(queue, DESTINATION1);
        verifyEmptyQueue(queue);
    }

    function test_addToTail_ThenPop() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        verifyOnlyOneAddress(queue, DESTINATION1);

        WithdrawalQueue.popAddress(queue, DESTINATION1);
        verifyEmptyQueue(queue);
    }

    function test_PopFrom_Top() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);
        // stack looks like 1, 2, 3

        WithdrawalQueue.popAddress(queue, DESTINATION1);
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION3);
    }

    function test_PopFrom_Middle() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);
        // stack looks like 1, 2, 3

        WithdrawalQueue.popAddress(queue, DESTINATION2);

        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION3);
    }

    function test_Pop_Last() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);
        // stack looks like 1, 2, 3

        WithdrawalQueue.popAddress(queue, DESTINATION3);

        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION2);
    }

    function test_add_many_then_remove_all() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);
        WithdrawalQueue.addToTail(queue, DESTINATION4);
        WithdrawalQueue.addToTail(queue, DESTINATION5);
        // looks like (1,2,3,4,5)

        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION5);
        // assertEq(queue.size, 5);

        WithdrawalQueue.popAddress(queue, DESTINATION1);
        // looks like (2,3,4,5)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION5);
        // assertEq(queue.size, 4);

        WithdrawalQueue.popAddress(queue, DESTINATION4);
        // looks like (2,3,5)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION5);
        // assertEq(queue.size, 3);

        WithdrawalQueue.popAddress(queue, DESTINATION5);
        // looks like (2,3)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION3);
        // assertEq(queue.size, 2);

        WithdrawalQueue.popAddress(queue, DESTINATION3);
        // looks like (2)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION2);
        // assertEq(queue.size, 1);

        WithdrawalQueue.popAddress(queue, DESTINATION2);
        // looks like ()
        verifyEmptyQueue(queue);
    }

    function test_sizeOf_ReturnsZeroWhenEmpty() public {
        assertEq(WithdrawalQueue.sizeOf(queue), 0, "length");
    }

    function test_sizeOf_ReturnsNumOfItemsAdded() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);

        assertEq(WithdrawalQueue.sizeOf(queue), 3, "length");
    }

    function test_sizeOf_DecreasesWhenItemsPopped() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);

        WithdrawalQueue.popHead(queue);

        assertEq(WithdrawalQueue.sizeOf(queue), 2, "length");
    }

    function test_size_ReturnsZeroWhenAllItemsRemoved() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);

        WithdrawalQueue.popHead(queue);
        WithdrawalQueue.popHead(queue);
        WithdrawalQueue.popHead(queue);

        assertEq(WithdrawalQueue.sizeOf(queue), 0, "length");
    }

    function test_popHead_DoesntRevertOnEmpty() public {
        address a = WithdrawalQueue.popHead(queue);
        assertEq(a, address(0), "address");
    }

    function test_popHead_RemovesTopItem() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);

        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1, "pre");

        address a = WithdrawalQueue.popHead(queue);

        assertEq(a, DESTINATION1, "address");
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2, "post");
    }

    // // ############################## TEST PERMUTE Queue ############################

    function test_permute_queue() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION3);
        WithdrawalQueue.addToTail(queue, DESTINATION4);
        WithdrawalQueue.addToTail(queue, DESTINATION5);
        // looks like (1,2,3,4,5)

        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION1);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION5);

        WithdrawalQueue.addToTail(queue, DESTINATION1);
        // looks like (2,3,4,5,1)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);

        WithdrawalQueue.addToTail(queue, DESTINATION4);
        // looks like (2,3,5,1,4)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION4);

        WithdrawalQueue.popAddress(queue, DESTINATION4);
        // looks like (2,3,5,1)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);

        WithdrawalQueue.popAddress(queue, DESTINATION5);
        // looks like (2,3,1)
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION2);
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION1);
    }

    function test_getList_ReturnsEmptyArrayWhenEmpty() public {
        address[] memory list = WithdrawalQueue.getList(queue);
        assertEq(list.length, 0, "listLength");
    }

    function test_getList_EnumeratesFromHeadToTail() public {
        // Order should be 3,1,2,3,4,5
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION4);
        WithdrawalQueue.addToTail(queue, DESTINATION5);
        WithdrawalQueue.addToHead(queue, DESTINATION3);

        // Verify the head and tail are as we expect
        assertEq(WithdrawalQueue.peekHead(queue), DESTINATION3, "head");
        assertEq(WithdrawalQueue.peekTail(queue), DESTINATION5, "tail");

        // Check the actual list
        address[] memory list = WithdrawalQueue.getList(queue);
        assertEq(list[0], DESTINATION3, "destination3");
        assertEq(list[1], DESTINATION1, "destination1");
        assertEq(list[2], DESTINATION2, "destination2");
        assertEq(list[3], DESTINATION4, "destination4");
        assertEq(list[4], DESTINATION5, "destination5");
    }

    function test_getList_ReturnedCountMatchesSizeOf() public {
        WithdrawalQueue.addToTail(queue, DESTINATION1);
        WithdrawalQueue.addToTail(queue, DESTINATION2);
        WithdrawalQueue.addToTail(queue, DESTINATION4);
        WithdrawalQueue.addToTail(queue, DESTINATION5);
        WithdrawalQueue.addToHead(queue, DESTINATION3);

        address[] memory list = WithdrawalQueue.getList(queue);
        assertEq(WithdrawalQueue.sizeOf(queue), list.length, "length");
    }

    // ############################## HELPER FUNCTIONS ##############################

    function verifyEmptyQueue(
        StructuredLinkedList.List storage _queue
    ) internal {
        assertTrue(WithdrawalQueue.isEmpty(_queue));
    }

    function verifyOnlyOneAddress(StructuredLinkedList.List storage _queue, address expectedAddr) internal {
        assertTrue(WithdrawalQueue.addressExists(_queue, expectedAddr));
        assertEq(WithdrawalQueue.peekHead(_queue), expectedAddr);
        assertEq(WithdrawalQueue.peekTail(_queue), expectedAddr);
    }
}
