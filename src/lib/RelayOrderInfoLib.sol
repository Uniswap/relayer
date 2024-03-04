// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrderInfo} from "../base/ReactorStructs.sol";

/// @notice Handles the EIP712 defined typehash and hashing for RelayOrderInfo
library RelayOrderInfoLib {
    bytes internal constant RELAY_ORDER_INFO_TYPESTRING = abi.encodePacked(
        "RelayOrderInfo(", "address reactor,", "address swapper,", "uint256 nonce,", "uint256 deadline)"
    );

    bytes32 internal constant RELAY_ORDER_INFO_TYPEHASH = keccak256(RELAY_ORDER_INFO_TYPESTRING);

    /// @notice Hashes the orderInfo
    /// @param orderInfo The info to hash
    /// @return The hash of the info
    function hash(RelayOrderInfo memory orderInfo) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RELAY_ORDER_INFO_TYPEHASH, orderInfo.reactor, orderInfo.swapper, orderInfo.nonce, orderInfo.deadline
            )
        );
    }
}
