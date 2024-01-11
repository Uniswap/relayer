// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {RelayOrderLib} from "./RelayOrderLib.sol";
import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

import "forge-std/console2.sol";

library ResolvedRelayOrderLib {
    function transferInputTokens(ResolvedRelayOrder memory order, IPermit2 permit2) internal {
        console2.log("permit2Call");
        uint256 gasLeft = gasleft();
        permit2.permitWitnessTransferFrom(
            order.permit, order.details, order.swapper, order.hash, RelayOrderLib.PERMIT2_ORDER_TYPE, order.sig
        );
        console2.log(gasLeft - gasleft());
    }

    function executeActions(ResolvedRelayOrder memory order) internal {
        // actions are encoded as (address target, uint256 value, bytes data)[]
        uint256 actionsLength = order.actions.length;
        for (uint256 i = 0; i < actionsLength;) {
            (address target, uint256 value, bytes memory data) = abi.decode(order.actions[i], (address, uint256, bytes));
            console2.log("action call");
            uint256 gasLeft = gasleft();
            (bool success, bytes memory result) = target.call{value: value}(data);
            console2.log(gasLeft - gasleft());
            if (!success) {
                // bubble up all errors, including custom errors which are encoded like functions
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            unchecked {
                i++;
            }
        }
    }
}
