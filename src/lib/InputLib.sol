// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input} from "../base/ReactorStructs.sol";

/// @notice Handles the EIP712 defined typehash and hashing for Input
library InputLib {
    bytes internal constant INPUT_TYPESTRING =
        abi.encodePacked("Input(", "address token,", "uint256 amount,", "address recipient)");
    bytes32 internal constant INPUT_TYPEHASH = keccak256(INPUT_TYPESTRING);

    /// @notice Hashes the input
    /// @param input The input to hash
    /// @return The hash of the input
    function hash(Input memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TYPEHASH, input.token, input.amount, input.recipient));
    }
}
