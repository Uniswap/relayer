// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedRelayOrder} from "../base/ReactorStructs.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor {
    /// @notice Execute a single order
    /// @param order The order definition and valid signature to execute
    function execute(SignedOrder calldata signedOrder) external returns (ResolvedRelayOrder memory order);

    /// @notice Execute the given orders at once
    /// @param orders The order definitions and valid signatures to execute
    function executeBatch(SignedOrder[] calldata orders) external;
}
