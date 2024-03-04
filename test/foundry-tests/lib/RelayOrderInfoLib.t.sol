// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayOrderInfo} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderInfoLib} from "../../../src/lib/RelayOrderInfoLib.sol";
import {RelayOrderInfoBuilder} from "../util/RelayOrderInfoBuilder.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract RelayOrderInfoTest is Test {
    using RelayOrderInfoBuilder for RelayOrderInfo;

    // Note: This doesn't check for 712 correctness, just accounts for accidental changes to the lib file
    function test_RelayOrderInfoTypestring_isCorrect() public {
        bytes memory typestring = "RelayOrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline)";
        assertEq(typestring, RelayOrderInfoLib.RELAY_ORDER_INFO_TYPESTRING);
        assertEq(keccak256(typestring), RelayOrderInfoLib.RELAY_ORDER_INFO_TYPEHASH);
    }

    function test_hash_isEqual() public {
        address reactor = makeAddr("reactor");
        RelayOrderInfo memory info0 = RelayOrderInfoBuilder.init(reactor);
        RelayOrderInfo memory info1 = RelayOrderInfoBuilder.init(reactor);
        assertEq(RelayOrderInfoLib.hash(info0), RelayOrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_reactor() public {
        address reactor0 = address(0xcafe);
        address reactor1 = address(0xface);
        RelayOrderInfo memory info0 = RelayOrderInfoBuilder.init(reactor0);
        RelayOrderInfo memory info1 = RelayOrderInfoBuilder.init(reactor1);
        assertTrue(RelayOrderInfoLib.hash(info0) != RelayOrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_swapper() public {
        address reactor = makeAddr("reactor");
        RelayOrderInfo memory info0 = RelayOrderInfoBuilder.init(reactor);
        info0 = info0.withSwapper(address(0x222));
        RelayOrderInfo memory info1 = RelayOrderInfoBuilder.init(reactor);
        info1 = info1.withSwapper(address(0x333));
        assertTrue(RelayOrderInfoLib.hash(info0) != RelayOrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_nonce() public {
        address reactor = makeAddr("reactor");
        RelayOrderInfo memory info0 = RelayOrderInfoBuilder.init(reactor);
        info0 = info0.withNonce(1);
        RelayOrderInfo memory info1 = RelayOrderInfoBuilder.init(reactor);
        info1 = info1.withNonce(2);
        assertTrue(RelayOrderInfoLib.hash(info0) != RelayOrderInfoLib.hash(info1));
    }

    function test_hash_isDifferentBy_deadline() public {
        address reactor = makeAddr("reactor");
        RelayOrderInfo memory info0 = RelayOrderInfoBuilder.init(reactor);
        info0 = info0.withDeadline(100);
        RelayOrderInfo memory info1 = RelayOrderInfoBuilder.init(reactor);
        info1 = info1.withDeadline(200);
        assertTrue(RelayOrderInfoLib.hash(info0) != RelayOrderInfoLib.hash(info1));
    }
}
