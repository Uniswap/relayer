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
import {RelayOrderLib, RelayOrder} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";
import {RelayDecayLib} from "../lib/RelayDecayLib.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is ReactorEvents, ReactorErrors, ReentrancyGuard, IRelayOrderReactor {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    using RelayDecayLib for InputTokenWithRecipient[];

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
    }

    // write execute such that we prepare,execute, and fill per order
    function execute(SignedOrder calldata order) external payable nonReentrant {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _handleResolvedOrders(resolvedOrders);
    }

    function executeBatch(SignedOrder[] calldata orders) external payable nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _handleResolvedOrders(resolvedOrders);
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

    /// @notice validate the relay order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(RelayOrder memory order) private view {
        if (order.info.deadline < order.decayEndTime) {
            revert DeadlineBeforeEndTime();
        }

        if (block.timestamp > order.info.deadline) {
            revert DeadlinePassed();
        }

        if (order.decayEndTime < order.decayStartTime) {
            revert OrderEndTimeBeforeStartTime();
        }

        if (address(this) != address(order.info.reactor)) {
            revert InvalidReactor();
        }
        // TODO: add additional validations related to relayed actions, if desired
    }

    function _handleResolvedOrders(ResolvedRelayOrder[] memory resolvedOrders) private {
        unchecked {
            for (uint256 i = 0; i < resolvedOrders.length; i++) {
                ResolvedRelayOrder memory order = resolvedOrders[i];
                order.transferInputTokens(permit2); // meh I don't like that you pass the address :/
                order.executeActions();
                emit Fill(order.hash, msg.sender, order.info.swapper, order.info.nonce);
            }
        }
    }

    receive() external payable {
        // receive native asset to support native output
    }
}
