// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder, OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";
import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {ResolvedRelayOrder, OutputToken} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {IRelayOrderReactorCallback} from "../interfaces/IRelayOrderReactorCallback.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {RelayOrderLib, RelayOrder, RelayInput, RelayOutput} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";
import {RelayDecayLib} from "../lib/RelayDecayLib.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is IReactor, ReactorEvents, ReactorErrors, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using Permit2Lib for ResolvedRelayOrder;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    using RelayDecayLib for RelayInput[];
    using RelayDecayLib for RelayOutput[];

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
    }

    function execute(SignedOrder calldata order) external payable nonReentrant {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @notice callbacks allow fillers to perform additional actions after the order is executed
    /// example, to transfer in tokens to fill orders where users are owed additional amounts
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData)
        external
        payable
        nonReentrant
    {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        IRelayOrderReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);
        _fill(resolvedOrders);
    }

    function executeBatch(SignedOrder[] calldata orders) external payable nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @notice callbacks allow fillers to perform additional actions after the order is executed
    /// example, to transfer in tokens to fill orders where users are owed additional amounts
    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        payable
        nonReentrant
    {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        IRelayOrderReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);
        _fill(resolvedOrders);
    }

    function _execute(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // actions are encoded as (address target, uint256 value, bytes data)[]
        for (uint256 i = 0; i < ordersLength;) {
            ResolvedRelayOrder memory order = orders[i];
            uint256 actionsLength = order.actions.length;
            for (uint256 j = 0; j < actionsLength;) {
                if (order.actions[j].length != 0) {
                    (address target, uint256 value, bytes memory data) =
                        abi.decode(order.actions[j], (address, uint256, bytes));
                    (bool success, bytes memory result) = target.call{value: value}(data);
                    if (!success) {
                        // bubble up all errors, including custom errors which are encoded like functions
                        assembly {
                            revert(add(result, 0x20), mload(result))
                        }
                    }
                }
                unchecked {
                    j++;
                }
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice validates and transfers input tokens in preparation for order fill
    /// @param orders The orders to prepare
    function _prepare(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory order = orders[i];

                order.validate(msg.sender);

                // Since relay order inputs specify recipients we don't pass in recipient here
                transferInputTokens(order);
            }
        }
    }

    /// @notice emits a Fill event for each order
    /// @notice all output token checks must be done in the encoded actions within the order
    /// @param orders The orders that have been filled
    function _fill(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // attempt to transfer all currencies to all recipients
        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory resolvedOrder = orders[i];
                uint256 outputsLength = resolvedOrder.outputs.length;
                for (uint256 j = 0; j < outputsLength; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];
                    output.token.transferFillFromBalance(output.recipient, output.amount);
                }

                emit Fill(orders[i].hash, msg.sender, resolvedOrder.info.swapper, resolvedOrder.info.nonce);
            }
        }
    }

    receive() external payable {
        // receive native asset to support native output
    }

    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        returns (ResolvedRelayOrder memory resolvedOrder)
    {
        RelayOrder memory order = abi.decode(signedOrder.order, (RelayOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedRelayOrder({
            info: order.info,
            actions: order.actions,
            inputs: order.inputs.decay(),
            outputs: order.outputs.decay(),
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    function transferInputTokens(ResolvedRelayOrder memory order) internal {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(),
            order.info.swapper,
            order.hash,
            RelayOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the relay order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(RelayOrder memory order) internal pure {
        uint256 inputsLength = order.inputs.length;
        uint256 outputsLength = order.outputs.length;
        for (uint256 i = 0; i < inputsLength; i++) {
            if (order.info.deadline < order.inputs[i].decayEndTime) {
                revert DeadlineBeforeEndTime();
            }
            if (order.inputs[i].decayEndTime < order.inputs[i].decayStartTime) {
                revert OrderEndTimeBeforeStartTime();
            }
        }

        for (uint256 i = 0; i < outputsLength; i++) {
            if (order.info.deadline < order.outputs[i].decayEndTime) {
                revert DeadlineBeforeEndTime();
            }
            if (order.outputs[i].decayEndTime < order.outputs[i].decayStartTime) {
                revert OrderEndTimeBeforeStartTime();
            }
        }

        // TODO: add additional validations related to relayed actions, if desired
    }
}
