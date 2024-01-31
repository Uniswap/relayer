// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedTransferDetails, RelayOrder} from "../base/ReactorStructs.sol";
import {IMulticall} from "./IMulticall.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor is IMulticall {
    /// @notice Execute a single order
    // / @param signedOrder The order definition and valid signature to execute
    function execute(RelayOrder calldata order, bytes calldata sig) external returns (ResolvedTransferDetails memory);
}
