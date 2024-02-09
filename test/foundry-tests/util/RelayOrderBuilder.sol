// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input, OrderInfo, RelayOrder, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {InputBuilder} from "./InputBuilder.sol";
import {OrderInfoBuilder} from "./OrderInfoBuilder.sol";
import {FeeEscalatorBuilder} from "./FeeEscalatorBuilder.sol";

library RelayOrderBuilder {
    using OrderInfoBuilder for OrderInfo;

    function init(OrderInfo memory info, Input[] memory inputs, FeeEscalator memory fee)
        internal
        view
        returns (RelayOrder memory)
    {
        return RelayOrder({info: info, inputs: inputs, fee: fee, actions: new bytes[](0)});
    }

    function withActions(RelayOrder memory order, bytes[] memory _actions) internal pure returns (RelayOrder memory) {
        order.actions = _actions;
        return order;
    }

    function initDefault(ERC20 token, address reactor, address swapper) internal view returns (RelayOrder memory) {
        Input[] memory inputs = new Input[](1);
        // Default input does not decay.
        inputs[0] = InputBuilder.init(token);

        return RelayOrder({
            info: OrderInfoBuilder.init(reactor).withSwapper(swapper),
            inputs: inputs,
            fee: FeeEscalatorBuilder.init(token),
            actions: new bytes[](0)
        });
    }
}
