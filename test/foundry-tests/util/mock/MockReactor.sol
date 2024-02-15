// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrder} from "../../../../src/base/ReactorStructs.sol";
import {RelayOrderLib} from "../../../../src/lib/RelayOrderLib.sol";

contract MockReactor {
    function validate(RelayOrder memory order) public view {
        RelayOrderLib.validate(order);
    }
}
