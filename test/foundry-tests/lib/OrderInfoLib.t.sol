// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo} from "../../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../../src/lib/OrderInfoLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract OrderInfoTest is Test {
    using OrderInfoBuilder for OrderInfo;

    // Note: This doesn't check for 712 correctness, just accounts for accidental changes to the lib file
    function test_OrderInfoTypestring_isCorrect() public {
        bytes memory typestring = "OrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline)";
        assertEq(typestring, OrderInfoLib.ORDER_INFO_TYPESTRING);
        assertEq(keccak256(typestring), OrderInfoLib.ORDER_INFO_TYPEHASH);
    }

    function test_hash_isEqual() public {
        address reactor = makeAddr("reactor");
        OrderInfo memory info0 = OrderInfoBuilder.init(reactor);
        OrderInfo memory info1 = OrderInfoBuilder.init(reactor);
        assertEq(OrderInfoLib.hash(info0), OrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_reactor() public {
        address reactor0 = address(0xcafe);
        address reactor1 = address(0xface);
        OrderInfo memory info0 = OrderInfoBuilder.init(reactor0);
        OrderInfo memory info1 = OrderInfoBuilder.init(reactor1);
        assertTrue(OrderInfoLib.hash(info0) != OrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_swapper() public {
        address reactor = makeAddr("reactor");
        OrderInfo memory info0 = OrderInfoBuilder.init(reactor);
        info0 = info0.withSwapper(address(0x222));
        OrderInfo memory info1 = OrderInfoBuilder.init(reactor);
        info1 = info1.withSwapper(address(0x333));
        assertTrue(OrderInfoLib.hash(info0) != OrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_nonce() public {
        address reactor = makeAddr("reactor");
        OrderInfo memory info0 = OrderInfoBuilder.init(reactor);
        info0 = info0.withNonce(1);
        OrderInfo memory info1 = OrderInfoBuilder.init(reactor);
        info1 = info1.withNonce(2);
        assertTrue(OrderInfoLib.hash(info0) != OrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_deadline() public {
        address reactor = makeAddr("reactor");
        OrderInfo memory info0 = OrderInfoBuilder.init(reactor);
        info0 = info0.withDeadline(100);
        OrderInfo memory info1 = OrderInfoBuilder.init(reactor);
        info1 = info1.withDeadline(200);
        assertTrue(OrderInfoLib.hash(info0) != OrderInfoLib.hash(info1));
    }
}
