// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IMulticall {
    /// @notice Call multiple functions in the current contract.
    /// @param data Encoded function data for each of the calls.
    /// @return results Return values from each of the calls.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
