// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

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

// /// @dev Note that a user still signs over a spender address
// struct PermitBatchTransferFrom {
//     // the tokens and corresponding amounts permitted for a transfer
//     TokenPermissions[] permitted;
//     // a unique value for every token owner's signature to prevent signature replays
//     uint256 nonce;
//     // deadline on the permit signature
//     uint256 deadline;
// }

/// @dev generic order information
///  should be included as the first field in any concrete order types
struct OrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the swapper
    // signature commits to the specific reactor that they trust to fill their order properly
    IReactor reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by swapper
    address swapper;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid
    uint256 deadline;
}

// /// @dev Note that a user still signs over a spender address
// struct PermitBatchTransferFrom {
//     // the tokens and corresponding amounts permitted for a transfer
//     TokenPermissions[] permitted;
//     // a unique value for every token owner's signature to prevent signature replays
//     uint256 nonce;
//     // deadline on the permit signature
//     uint256 deadline;
// }

/// @notice The token and amount details for a transfer signed in the permit transfer signature
struct TokenPermissions {
    // ERC20 token address
    address token;
    // the maximum amount that can be spent
    uint256 amount;
}

/// @notice Every RelayOrder input is defined by a token, recipient,
/// and amounts that define the start and end amounts on the decay curve.
struct Input {
    address token;
    address recipient;
    uint256 startAmount;
    uint256 maxAmount;
}

// struct SignatureTransferDetails {
//     // recipient address
//     address to;
//     // spender requested amount
//     uint256 requestedAmount;
// }

struct ResolvedRelayOrder {
    address swapper;
    bytes[] actions;
    ISignatureTransfer.PermitBatchTransferFrom permit;
    ISignatureTransfer.SignatureTransferDetails[] details; // built from recipient and decayed amounts
    bytes sig;
    bytes32 hash;
}
