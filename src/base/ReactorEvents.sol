// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice events emitted by the reactor
interface ReactorEvents {
    /// @notice Emitted when an order is filled
    /// @param orderHash The hash of the order that was filled
    /// @param filler The address which executed the fill
    /// @param nonce The nonce of the filled order
    /// @param swapper The swapper of the filled order
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);
}
