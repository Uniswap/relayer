// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrder} from "../base/ReactorStructs.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {RelayOrder} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import "forge-std/console2.sol";

// TODO: Add multicall support.
contract RelayOrderQuoter {
    // 32 bytes since OrderInfo struct is statically encoded and the reactor is the first member of that struct.
    uint256 constant ORDER_INFO_OFFSET = 32;

    // ISignatureTransfer.SignatureTransferDetails with 1 element in it will be encoded:
    // 32 bytes, location of first param
    // 32 bytes, length
    // 32 bytes, address
    // 32 bytes, amount
    uint256 constant MIN_VALID_REASON_LENGTH = 128;

    function quote(bytes calldata order, bytes calldata sig, address feeRecipient)
        external
        returns (ISignatureTransfer.SignatureTransferDetails[] memory result)
    {
        bytes memory selector =
            abi.encodeWithSelector(RelayOrderQuoter.executeAndRevert.selector, order, sig, feeRecipient);
        (bool success, bytes memory reason) = address(this).call(selector);
        if (!success) {
            result = parseRevertReason(reason);
        }
    }

    function executeAndRevert(bytes calldata order, bytes calldata sig, address feeRecipient) external {
        ISignatureTransfer.SignatureTransferDetails[] memory result =
            IRelayOrderReactor(getReactor(order)).execute(SignedOrder(order, sig), feeRecipient);
        bytes memory encodedOrder = abi.encode(result);
        assembly {
            revert(add(32, encodedOrder), mload(encodedOrder))
        }
    }

    /// TODO: Definitely overkill but keeping it for now since we are still using SignedOrder as the arg for execute and it parallels the UniswapX order quoter.
    function getReactor(bytes memory order) public pure returns (IRelayOrderReactor reactor) {
        assembly {
            let orderInfoOffsetPointer := add(order, ORDER_INFO_OFFSET)
            reactor := mload(add(orderInfoOffsetPointer, mload(orderInfoOffsetPointer)))
        }
    }

    /// @notice Return the order info of a given order (abi-encoded bytes).
    /// @param order abi-encoded order, including `reactor` as the first encoded struct member
    function parseRevertReason(bytes memory reason)
        private
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory order)
    {
        // TODO: Can an invalid revert be > min valid reason length?
        console2.log(reason.length);
        if (reason.length < MIN_VALID_REASON_LENGTH) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ISignatureTransfer.SignatureTransferDetails[]));
        }
    }
}
