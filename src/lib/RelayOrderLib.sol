// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";
import {OrderInfoLib} from "UniswapX/src/lib/OrderInfoLib.sol";

/// @dev An amount of input tokens that increases linearly over time
struct RelayInput {
    // The ERC20 token address
    ERC20 token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

/// @dev An amount of output tokens that decreases linearly over time
struct RelayOutput {
    // The ERC20 token address (or native ETH address)
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

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
    RelayInput[] inputs;
    // The tokens that must be received to satisfy the order
    RelayOutput[] outputs;
}

/// @notice helpers for handling relay order objects
library RelayOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes private constant INPUT_TOKEN_TYPE =
        "RelayInput(address token,uint256 startAmount,uint256 endAmount,address recipient)";

    bytes private constant OUTPUT_TOKEN_TYPE =
        "RelayOutput(address token,uint256 startAmount,uint256 endAmount,address recipient)";

    bytes32 private constant INPUT_TOKEN_TYPE_HASH = keccak256(INPUT_TOKEN_TYPE);
    bytes32 private constant OUTPUT_TOKEN_TYPE_HASH = keccak256(OUTPUT_TOKEN_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "RelayOrder(",
        "OrderInfo info,",
        "uint256 decayStartTime,",
        "uint256 decayEndTime,",
        "bytes[] actions,",
        "RelayInput[] inputs,",
        "RelayOutput[] outputs)",
        INPUT_TOKEN_TYPE,
        OrderInfoLib.ORDER_INFO_TYPE,
        OUTPUT_TOKEN_TYPE_HASH
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("RelayOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice returns the hash of an input token struct
    function hash(RelayInput memory input) private pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TOKEN_TYPE_HASH, input.token, input.startAmount, input.endAmount));
    }

    /// @notice returns the hash of an output token struct
    function hash(RelayOutput memory output) private pure returns (bytes32) {
        return keccak256(
            abi.encode(OUTPUT_TOKEN_TYPE_HASH, output.token, output.startAmount, output.endAmount, output.recipient)
        );
    }

    /// @notice returns the hash of an input token struct
    function hash(RelayInput[] memory inputs) private pure returns (bytes32) {
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

    function hash(RelayOutput[] memory outputs) private pure returns (bytes32) {
        unchecked {
            bytes memory packedHashes = new bytes(32 * outputs.length);

            for (uint256 i = 0; i < outputs.length; i++) {
                bytes32 outputHash = hash(outputs[i]);
                assembly {
                    mstore(add(add(packedHashes, 0x20), mul(i, 0x20)), outputHash)
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
                hash(order.inputs),
                hash(order.outputs)
            )
        );
    }
}
