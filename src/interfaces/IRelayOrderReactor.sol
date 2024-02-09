// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {Input} from "../base/ReactorStructs.sol";
import {IMulticall} from "./IMulticall.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor is IMulticall {
    /// @notice Validates a user's relayed request, sends tokens to relevant addresses, and executes the relayed actions.
    /// @param signedOrder Contains the raw relay order and signature bytes.
    /// @param feeRecipient The address to send the user's fee input.
    /// @return Inputs The resolved amounts and details for the token transfers.
    /// @dev Batch execute is enabled by using multicall.
    function execute(SignedOrder calldata signedOrder, address feeRecipient) external returns (Input[] memory Inputs);

    /// @notice Execute a signed 2612-style permit.
    /// The transaction will revert if the permit cannot be executed.
    /// @dev A permit request can be combined with an execute action through multicall.
    function permit(ERC20 token, bytes calldata data) external;
}
