// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor {
    /// @notice Execute a single order
    /// @param order The order definition and valid signature to execute
    function execute(SignedOrder calldata order) external;
}
