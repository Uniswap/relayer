// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder, OrderInfo, OutputToken} from "UniswapX/src/base/ReactorStructs.sol";
import {IReactorCallback} from "UniswapX/src/interfaces/IReactorCallback.sol";
import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {ProtocolFees} from "UniswapX/src/base/ProtocolFees.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {InputTokenWithRecipient, ResolvedRelayOrder} from "../base/ReactorStructs.sol";
import {CurrencyLibrary, NATIVE} from "../lib/CurrencyLibrary.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {RelayOrderLib, RelayOrder, ActionType} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";
import {RelayDecayLib} from "../lib/RelayDecayLib.sol";

/// @notice Reactor for relaying calls to UniversalRouter onchain
/// @dev This reactor only supports V2/V3 swaps, do NOT attempt to use other Universal Router commands
contract RelayOrderReactor is ReactorEvents, ReactorErrors, ReentrancyGuard, IReactor {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using Permit2Lib for ResolvedRelayOrder;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    using RelayDecayLib for InputTokenWithRecipient[];

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    address public immutable universalRouter;

    constructor(IPermit2 _permit2, address _universalRouter) {
        permit2 = _permit2;
        universalRouter = _universalRouter;
    }

    function execute(SignedOrder calldata order) external payable nonReentrant {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        _fill(resolvedOrders);
    }

    function executeWithCallback(SignedOrder calldata, bytes calldata) external payable nonReentrant {
        revert ReactorCallbackNotSupported();
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

    function executeBatchWithCallback(SignedOrder[] calldata, bytes calldata) external payable nonReentrant {
        revert ReactorCallbackNotSupported();
    }

    function _execute(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // actions are encoded as (ActionType actionType, bytes actionData)[]
        for (uint256 i = 0; i < ordersLength; i++) {
            ResolvedRelayOrder memory order = orders[i];
            uint256 actionsLength = order.actions.length;
            for (uint256 j = 0; j < actionsLength;) {
                (ActionType actionType, bytes memory actionData) = abi.decode(order.actions[j], (ActionType, bytes));
                if (actionType == ActionType.UniversalRouter) {
                    /// @dev to use universal router integration, this contract must be recipient of all output tokens
                    (bool success,) = universalRouter.call(actionData);
                    if (!success) revert CallFailed();
                }
                // Give Permit2 max approval on the reactor
                else if (actionType == ActionType.ApprovePermit2) {
                    (address token) = abi.decode(actionData, (address));
                    if (token == address(0)) revert InvalidToken();
                    if (ERC20(token).allowance(address(this), address(permit2)) == 0) {
                        ERC20(token).approve(address(permit2), type(uint256).max);
                    }
                    permit2.approve(token, universalRouter, type(uint160).max, type(uint48).max);
                }
                // Catch unsupported action types
                else {
                    revert UnsupportedAction();
                }
                unchecked {
                    j++;
                }
            }
        }
    }

    /// @notice validates, injects fees, and transfers input tokens in preparation for order fill
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

    /// @notice fills a list of orders, ensuring all outputs are satisfied
    /// @param orders The orders to fill
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

        // refund any remaining ETH to the filler. Only occurs when filler sends more ETH than required to
        // `execute()` or `executeBatch()`, or when there is excess contract balance remaining from others
        // incorrectly calling execute/executeBatch without direct filler method but with a msg.value
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(msg.sender, address(this).balance);
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
            inputs: order.inputs.decay(order.decayStartTime, order.decayEndTime),
            outputs: order.outputs,
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
        if (order.info.deadline < order.decayEndTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.decayEndTime < order.decayStartTime) {
            revert OrderEndTimeBeforeStartTime();
        }

        // TODO: add additional validations related to relayed actions, if desired
    }
}
