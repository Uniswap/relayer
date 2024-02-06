// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;

import {OrderInfo} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";

library OrderInfoBuilder {
    function init(address reactor) internal view returns (OrderInfo memory) {
        return OrderInfo({
            reactor: IRelayOrderReactor(reactor),
            swapper: address(0),
            nonce: 0,
            deadline: block.timestamp + 100
        });
    }

    function withSwapper(OrderInfo memory info, address _swapper) internal pure returns (OrderInfo memory) {
        info.swapper = _swapper;
        return info;
    }

    function withNonce(OrderInfo memory info, uint256 _nonce) internal pure returns (OrderInfo memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(OrderInfo memory info, uint256 _deadline) internal pure returns (OrderInfo memory) {
        info.deadline = _deadline;
        return info;
    }
}
