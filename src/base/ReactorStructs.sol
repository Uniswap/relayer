// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";

/// @dev Note that all of these fields are signed over. Some are hashed in the base permit and some are hashed in the passed in witness.
/// We construct the permit details and witness information.
struct RelayOrder {
    // Generic order info
    OrderInfo info;
    // Token info for onchain actions
    Input input;
    // The fee offered for the order
    FeeEscalator fee;
    // ecnoded data to execute onchain
    bytes actions;
}

/// @dev Generic order information
struct OrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the swapper
    // signature commits to the specific reactor that they trust to fill their order properly
    IRelayOrderReactor reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by swapper
    address swapper;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid
    uint256 deadline;
}

/// @notice Every Input is defined by a token, amount, and recipient,
/// @dev These values are signed by the user
struct Input {
    address token;
    uint256 amount;
    address recipient;
}

/// @notice A RelayOrder can specify an increasing fee over time to be paid
struct FeeEscalator {
    address token;
    uint256 startAmount;
    uint256 endAmount;
    // The time at which the fee starts to increase
    uint256 startTime;
    // The time at which the fee becomes static
    uint256 endTime;
    // The address to which the fee will be paid
    // Note that address(0) will send the fee to the recipient specified by the filler of the order
    address recipient;
}
