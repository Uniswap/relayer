// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";
import {OrderInfoLib} from "UniswapX/src/lib/OrderInfoLib.sol";
import {InputTokenWithRecipient} from "../base/ReactorStructs.sol";

/// @dev External struct used to specify simple relay orders
struct RelayOrder {
    // generic order information
    OrderInfo info;
    // The time at which the inputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // ecnoded actions to execute onchain
    bytes[] actions;
    // The tokens that the swapper will provide when settling the order
    InputTokenWithRecipient[] inputs;
}

/// @notice helpers for handling relay order objects
library RelayOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes private constant INPUT_TOKEN_TYPE =
        "InputTokenWithRecipient(address token,int256 amount,int256 maxAmount,address recipient)";

    bytes32 private constant INPUT_TOKEN_TYPE_HASH = keccak256(INPUT_TOKEN_TYPE);

    bytes internal constant RELAY_ORDER_TYPE = abi.encodePacked(
        "RelayOrder(",
        "OrderInfo info,",
        "uint256 decayStartTime,",
        "uint256 decayEndTime,",
        "bytes[] actions,",
        "InputTokenWithRecipient[] inputs)"
    );

    bytes internal constant ORDER_TYPE =
        abi.encodePacked(RELAY_ORDER_TYPE, INPUT_TOKEN_TYPE, OrderInfoLib.ORDER_INFO_TYPE);

    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked("RelayOrder witness)", RELAY_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE, TOKEN_PERMISSIONS_TYPE)
    );

    /// @notice returns the hash of an input token struct
    function hash(InputTokenWithRecipient memory input) private pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TOKEN_TYPE_HASH, input.token, input.amount, input.maxAmount, input.recipient));
    }

    /// @notice returns the hash of an input token struct
    function hash(InputTokenWithRecipient[] memory inputs) private pure returns (bytes32) {
        unchecked {
            bytes memory packedHashes = new bytes(32 * inputs.length);

            for (uint256 i = 0; i < inputs.length; i++) {
                bytes32 inputHash = hash(inputs[i]);
                assembly {
                    mstore(add(add(packedHashes, 0x20), mul(i, 0x20)), inputHash)
                }
            }

            return keccak256(packedHashes);
        }
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.hash(),
                order.decayStartTime,
                order.decayEndTime,
                order.actions,
                hash(order.inputs)
            )
        );
    }
}
