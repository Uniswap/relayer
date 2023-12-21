// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

/// @notice interface for a filler of relay orders that supports paying rebates to users
interface IRelayOrderRebateFiller {
    function reactorCallback(ResolvedRelayOrder memory order, bytes calldata callbackData) external payable;
}
