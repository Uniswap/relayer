// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {RelayOrderLib} from "./RelayOrderLib.sol";
import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

library ResolvedRelayOrderLib {
    function transferInputTokens(ResolvedRelayOrder memory order, IPermit2 permit2) internal {
        permit2.permitWitnessTransferFrom(
            order.permit, order.details, order.swapper, order.hash, RelayOrderLib.PERMIT2_ORDER_TYPE, order.sig
        );
    }
}
