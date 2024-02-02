// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";

/// @dev Note that all of these fields are signed over. Some are hashed in the base permit and some are hashed in the passed in witness.
/// We construct the permit details and witness information.
struct RelayOrder {
    // Generic order info
    OrderInfo info;
    // Token info for the onchain trade and the payout to fillers
    Input[] inputs;
    // The time at which the inputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // ecnoded actions to execute onchain
    bytes[] actions;
}

/// @dev generic order information
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

/// @notice Every RelayOrder input is defined by a token, recipient,
/// and amounts that define the start and end amounts on the decay curve.
/// @dev These values are signed by the user. address(0) will set the recipient at run-time to the passed in feeRecipient value.
struct Input {
    address token;
    address recipient;
    uint256 startAmount;
    uint256 maxAmount;
}

/// @notice Minimal information to return for a quoter.
struct ResolvedTransferDetails {
    ISignatureTransfer.SignatureTransferDetails[] transferDetails; // these are the resolved input amounts
    bytes32 orderHash;
}
