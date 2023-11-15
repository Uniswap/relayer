// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "UniswapX/src/interfaces/IValidationCallback.sol";
import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

library ResolvedRelayOrderLib {
    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();

    /// @notice thrown if the order has expired
    error DeadlinePassed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedRelayOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != address(resolvedOrder.info.reactor)) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.deadline) {
            revert DeadlinePassed();
        }

        // if (address(resolvedOrder.info.additionalValidationContract) != address(0)) {
        //     resolvedOrder.info.additionalValidationContract.validate(filler, resolvedOrder);
        // }
    }
}
