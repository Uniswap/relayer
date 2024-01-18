// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall {
    function multicall(bytes[] calldata data) public virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length;) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                // bubble up all errors, including custom errors which are encoded like functions
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
            unchecked {
                i++;
            }
        }
    }
}
