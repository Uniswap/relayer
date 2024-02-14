// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input, OrderInfo, RelayOrder, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {InputBuilder} from "./InputBuilder.sol";
import {OrderInfoBuilder} from "./OrderInfoBuilder.sol";
import {FeeEscalatorBuilder} from "./FeeEscalatorBuilder.sol";
import {MockUniversalRouter} from "./mock/MockUniversalRouter.sol";

library RelayOrderBuilder {
    using OrderInfoBuilder for OrderInfo;

    function init(OrderInfo memory info, Input memory input, FeeEscalator memory fee)
        internal
        pure
        returns (RelayOrder memory)
    {
        return RelayOrder({info: info, input: input, fee: fee, universalRouterCalldata: bytes("")});
    }

    function withUniversalRouterCalldata(RelayOrder memory order, bytes memory _universalRouterCalldata)
        internal
        pure
        returns (RelayOrder memory)
    {
        order.universalRouterCalldata = _universalRouterCalldata;
        return order;
    }

    function withFee(RelayOrder memory order, FeeEscalator memory _fee) internal pure returns (RelayOrder memory) {
        order.fee = _fee;
        return order;
    }

    function initDefault(ERC20 token, address reactor, address swapper) internal view returns (RelayOrder memory) {
        return RelayOrder({
            info: OrderInfoBuilder.init(reactor).withSwapper(swapper),
            input: InputBuilder.init(token),
            fee: FeeEscalatorBuilder.init(token),
            universalRouterCalldata: bytes("")
        });
    }
}
