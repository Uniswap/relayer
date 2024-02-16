// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Input} from "../../../src/base/ReactorStructs.sol";
import {InputLib} from "../../../src/lib/InputLib.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract InputLibTest is Test {
    using InputBuilder for Input;

    // Note: This doesn't check for 712 correctness, just accounts for accidental changes to the lib file
    function test_InputTypeString_isCorrect() public {
        bytes memory typestring = "Input(address token,uint256 amount,address recipient)";
        assertEq(typestring, InputLib.INPUT_TYPESTRING);
        assertEq(keccak256(typestring), InputLib.INPUT_TYPEHASH);
    }

    function test_hash_isEqual() public {
        address token = makeAddr("token");
        Input memory input0 = InputBuilder.init(ERC20(token));
        Input memory input1 = InputBuilder.init(ERC20(token));
        assertEq(InputLib.hash(input0), InputLib.hash(input1));
    }

    function test_hash_isDifferentBy_token() public {
        address token0 = address(0xfeed);
        address token1 = address(0xbeed);
        Input memory input0 = InputBuilder.init(ERC20(token0));
        Input memory input1 = InputBuilder.init(ERC20(token1));
        assertTrue(InputLib.hash(input0) != InputLib.hash(input1));
    }

    function test_hash_isDifferentBy_recipient() public {
        address token = makeAddr("token");
        Input memory input0 = InputBuilder.init(ERC20(token));
        input0 = input0.withRecipient(address(0xeee));
        Input memory input1 = InputBuilder.init(ERC20(token));
        input1 = input1.withRecipient(address(0xaaa));
        assertTrue(InputLib.hash(input0) != InputLib.hash(input1));
    }

    function test_hash_isDifferentBy_amount() public {
        address token = makeAddr("token");
        Input memory input0 = InputBuilder.init(ERC20(token));
        input0 = input0.withAmount(10);
        Input memory input1 = InputBuilder.init(ERC20(token));
        input1 = input1.withAmount(20);
        assertTrue(InputLib.hash(input0) != InputLib.hash(input1));
    }
}
