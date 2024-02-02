// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrder} from "../base/ReactorStructs.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {RelayOrder} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IMulticall} from "../interfaces/IMulticall.sol";

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
        bytes memory executeSelector =
            abi.encodeWithSelector(IRelayOrderReactor.execute.selector, SignedOrder(order, sig), feeRecipient);
        return _callSelf(address(getReactor(order)), executeSelector);
    }

    function quoteMulticall(bytes calldata multicallData, address reactor)
        external
        returns (ISignatureTransfer.SignatureTransferDetails[] memory result)
    {
        bytes memory multicallSelector = abi.encodeWithSelector(IMulticall.multicall.selector, multicallData);
        return _callSelf(reactor, multicallSelector);
    }

    function _callSelf(address reactor, bytes memory reactorSelector)
        internal
        returns (ISignatureTransfer.SignatureTransferDetails[] memory result)
    {
        bytes memory callAndRevert =
            abi.encodeWithSelector(RelayOrderQuoter.callAndRevert.selector, reactor, reactorSelector);
        (bool success, bytes memory reason) = address(this).call(callAndRevert);
        if (!success) {
            result = parseRevertReason(reason);
        }
    }

    function callAndRevert(address reactor, bytes calldata selector) external {
        (bool success, bytes memory result) = reactor.call(selector);
        assembly {
            revert(add(32, result), mload(result))
        }
    }

    /// @notice parses the reactor from the order
    function getReactor(bytes memory order) public pure returns (IRelayOrderReactor reactor) {
        assembly {
            let orderInfoOffsetPointer := add(order, ORDER_INFO_OFFSET)
            reactor := mload(add(orderInfoOffsetPointer, mload(orderInfoOffsetPointer)))
        }
    }

    /// @param order abi-encoded order, including `reactor` as the first encoded struct member
    function parseRevertReason(bytes memory reason)
        private
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory order)
    {
        // TODO: Can an invalid revert be > min valid reason length?
        console2.log(reason.length);
        console2.logBytes(reason);
        if (reason.length < MIN_VALID_REASON_LENGTH) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ISignatureTransfer.SignatureTransferDetails[]));
        }
    }
}
