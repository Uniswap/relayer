// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedInput} from "../base/ReactorStructs.sol";
import {IMulticall} from "./IMulticall.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor is IMulticall {
    /// @notice Validates a user's relayed request, sends tokens to relevant addresses, and executes the relayed actions.
    /// @param signedOrder Contains the raw relay order and signature bytes.
    /// @param feeRecipient The address to send the user's fee input.
    /// @dev Batch execute is enabled by using multicall.
    function execute(SignedOrder calldata signedOrder, address feeRecipient) external;

    /// @notice Execute a signed 2612-style permit.
    /// The transaction will revert if the permit cannot be executed.
    /// @dev A permit request can be combined with an execute action through multicall.
    function permit(ERC20 token, bytes calldata data) external;

    /// @notice Resolves the parameters of an order and returns the input amounts for the current time
    /// @param signedOrder Contains the raw relay order and signature bytes.
    /// @param feeRecipient The address to send the user's fee input.
    function resolve(SignedOrder calldata signedOrder, address feeRecipient)
        external
        view
        returns (ResolvedInput[] memory resolvedInputs);
}
