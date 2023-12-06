// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder, OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {InputTokenWithRecipient, ResolvedRelayOrder} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {RelayOrderLib, RelayOrder} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";
import {RelayDecayLib} from "../lib/RelayDecayLib.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is ReactorEvents, ReactorErrors, ReentrancyGuard, IRelayOrderReactor {
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

    function _execute(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // actions are encoded as (address target, uint256 value, bytes data)[]
        for (uint256 i = 0; i < ordersLength;) {
            ResolvedRelayOrder memory order = orders[i];
            uint256 actionsLength = order.actions.length;
            for (uint256 j = 0; j < actionsLength;) {
                (address target, uint256 value, bytes memory data) =
                    abi.decode(order.actions[j], (address, uint256, bytes));
                (bool success, bytes memory result) = target.call{value: value}(data);
                if (!success) {
                    // handle custom errors
                    if (result.length == 4) {
                        assembly {
                            revert(add(result, 0x20), mload(result))
                        }
                    }
                    // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                    if (result.length < 68) revert CallFailed();
                    assembly {
                        result := add(result, 0x04)
                    }
                    revert(abi.decode(result, (string)));
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
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory resolvedOrder = orders[i];
                // If there are negative inputs, we must transfer those to the swapper from the reactor's balance
                if (resolvedOrder.hasNegativeInputs()) {
                    // Transfer the negative inputs to the swapper
                    for (uint256 j = 0; j < resolvedOrder.inputs.length; j++) {
                        InputTokenWithRecipient memory input = resolvedOrder.inputs[j];
                        if (input.amount < 0) {
                            input.token.transfer(resolvedOrder.info.swapper, uint256(-input.amount));
                        }
                    }
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
            inputs: order.inputs.decay(order.decayStartTime, order.decayEndTime),
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
    }
}
