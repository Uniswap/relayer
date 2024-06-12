// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input, RelayOrderInfo, RelayOrder, FeeEscalator, Rebate} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {InputBuilder} from "./InputBuilder.sol";
import {RelayOrderInfoBuilder} from "./RelayOrderInfoBuilder.sol";
import {FeeEscalatorBuilder} from "./FeeEscalatorBuilder.sol";
import {RebateBuilder} from "./RebateBuilder.sol";
import {MockUniversalRouter} from "./mock/MockUniversalRouter.sol";

library RelayOrderBuilder {
    using RelayOrderInfoBuilder for RelayOrderInfo;

    function init(RelayOrderInfo memory info, Input memory input, FeeEscalator memory fee, Rebate memory rebate)
        internal
        pure
        returns (RelayOrder memory)
    {
        return RelayOrder({info: info, input: input, fee: fee, rebate: rebate, universalRouterCalldata: bytes("")});
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
            info: RelayOrderInfoBuilder.init(reactor).withSwapper(swapper),
            input: InputBuilder.init(token),
            fee: FeeEscalatorBuilder.init(token),
            rebate: RebateBuilder.init(token),
            universalRouterCalldata: bytes("")
        });
    }
}
