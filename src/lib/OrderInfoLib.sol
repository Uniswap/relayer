// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";

library OrderInfoLib {
    bytes internal constant ORDER_INFO_TYPESTRING =
        abi.encodePacked("OrderInfo(", "address reactor,", "address swapper,", "uint256 nonce,", "uint256 deadline)");

    bytes32 internal constant ORDER_INFO_TYPEHASH = keccak256(ORDER_INFO_TYPESTRING);

    function hash(OrderInfo memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_INFO_TYPEHASH, order.reactor, order.swapper, order.nonce, order.deadline));
    }
}
