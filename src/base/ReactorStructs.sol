// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

struct RelayOrder {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the swapper
    // signature commits to the specific reactor that they trust to fill their order properly
    IReactor reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by swapper
    address swapper;
    // The starting amount for the decay.
    uint256[] startAmounts;
    // Recipients for each input.
    address[] recipients;
    // The time at which the inputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // ecnoded actions to execute onchain
    bytes[] actions;
    // permit data for the order
    ISignatureTransfer.PermitBatchTransferFrom permit;
}

struct ResolvedRelayOrder {
    address swapper;
    bytes[] actions;
    ISignatureTransfer.PermitBatchTransferFrom permit;
    ISignatureTransfer.SignatureTransferDetails[] details; // built from recipient and decayed amounts
    bytes sig;
    bytes32 hash;
}
