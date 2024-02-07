// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedInput} from "../base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {IMulticall} from "../interfaces/IMulticall.sol";

/// @notice Quoter to be called off-chain to simulate orders to the RelayOrderReactor.
/// Supports calls to execute and multicall.
contract RelayOrderQuoter {
    // 32 bytes since OrderInfo struct is statically encoded and the reactor is the first member of that struct.
    uint256 constant ORDER_INFO_OFFSET = 32;

    // Execute and multicall return values with 1 element will be encoded as follows. They each have different minimum valid lengths.
    // ResolvedInput[]                                 |     bytes[]
    // 32 bytes, location of first param               |  32 bytes, location of the first param
    // 32 bytes, length                                |  32 bytes, length of the bytes array
    // 32 bytes, address                               |  32 bytes, location of the first element
    // 32 bytes, address                               |  32 bytes, value of the first element
    // 32 bytes , uint256
    uint256 constant MIN_VALID_REASON_LENGTH_EXECUTE = 160;
    uint256 constant MIN_VALID_REASON_LENGTH_MULTICALL = 128;

    function quote(bytes calldata order, bytes calldata sig, address feeRecipient)
        external
        returns (ResolvedInput[] memory result)
    {
        bytes memory executeSelector =
            abi.encodeWithSelector(IRelayOrderReactor.execute.selector, SignedOrder(order, sig), feeRecipient);
        (bool success, bytes memory reason) = _callSelf(address(getReactor(order)), executeSelector);
        if (!success) {
            result = parseRevertReason(reason);
        }
    }

    function quoteMulticall(address reactor, bytes[] calldata multicallData)
        external
        returns (bytes[] memory results)
    {
        bytes memory multicallSelector = abi.encodeWithSelector(IMulticall.multicall.selector, multicallData);
        (bool success, bytes memory reason) = _callSelf(reactor, multicallSelector);
        if (!success) {
            results = parseMulticallRevertReason(reason);
        }
    }

    function _callSelf(address reactor, bytes memory reactorSelector)
        internal
        returns (bool success, bytes memory reason)
    {
        bytes memory callAndRevertSelector =
            abi.encodeWithSelector(RelayOrderQuoter.callAndRevert.selector, reactor, reactorSelector);
        (success, reason) = address(this).call(callAndRevertSelector);
    }

    function callAndRevert(address reactor, bytes calldata selector) external {
        (, bytes memory result) = reactor.call(selector);
        assembly {
            revert(add(32, result), mload(result))
        }
    }

    /// @param order abi-encoded order, including `reactor` as the first encoded struct member
    function parseRevertReason(
        bytes memory reason // ISignatureTransfer[]
    ) private pure returns (ResolvedInput[] memory order) {
        // Note that the decoding will error if there are invalid results that error with data > min valid reason (128).
        if (reason.length < MIN_VALID_REASON_LENGTH_EXECUTE) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ResolvedInput[]));
        }
    }

    function parseMulticallRevertReason(bytes memory reason) private pure returns (bytes[] memory) {
        // Note that the decoding will error if there are invalid results that error with data > min valid reason (128).
        if (reason.length < MIN_VALID_REASON_LENGTH_MULTICALL) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (bytes[]));
        }
    }

    /// @notice parses the reactor from the order
    function getReactor(bytes memory order) public pure returns (IRelayOrderReactor reactor) {
        assembly {
            let orderInfoOffsetPointer := add(order, ORDER_INFO_OFFSET)
            reactor := mload(add(orderInfoOffsetPointer, mload(orderInfoOffsetPointer)))
        }
    }
}
