// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

/// @notice Callback for executing orders through a reactor.
interface IRelayOrderReactorCallback {
    /// @notice Called by the reactor after actions are exected in an order
    /// @param resolvedOrders Has inputs and outputs
    /// @param callbackData The callbackData specified for an order execution
    function reactorCallback(ResolvedRelayOrder[] memory resolvedOrders, bytes memory callbackData) external;
}
