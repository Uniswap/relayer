// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrder} from "../base/ReactorStructs.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {ResolvedRelayOrder, RelayOrder} from "../base/ReactorStructs.sol";

contract RelayOrderQuoter {
    // 32 instead of 64 because the RelayOrder is not dynamically encoded.
    uint256 constant ORDER_INFO_OFFSET = 32;

    function quote(bytes calldata order, bytes calldata sig) external returns (ResolvedRelayOrder memory result) {
        bytes memory selector = abi.encodeWithSelector(RelayOrderQuoter.executeAndRevert.selector, order, sig);
        (bool success, bytes memory reason) = address(this).call(selector);
        if (!success) {
            result = parseRevertReason(reason);
        }
    }

    function executeAndRevert(bytes calldata order, bytes calldata sig) external {
        ResolvedRelayOrder memory result = IRelayOrderReactor(getReactor(order)).execute(SignedOrder(order, sig));
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
    function parseRevertReason(bytes memory reason) private pure returns (ResolvedRelayOrder memory order) {
        // TODO: Why is this not 68? 4 bytes + 32 + 32
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ResolvedRelayOrder));
        }
    }
}
