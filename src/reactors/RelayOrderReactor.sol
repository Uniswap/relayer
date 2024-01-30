// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {ResolvedRelayOrder, RelayOrder} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {RelayOrderLib} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is ReactorEvents, ReactorErrors, ReentrancyGuard, IRelayOrderReactor {
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    /// @notice permit2 address used for token transfers and signature verification

    IPermit2 public immutable permit2;
    address public immutable universalRouter;

    constructor(IPermit2 _permit2, address _universalRouter) {
        permit2 = _permit2;
        universalRouter = _universalRouter;
    }

    function execute(SignedOrder calldata order) external nonReentrant {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _handleResolvedOrders(resolvedOrders);
    }

    function executeBatch(SignedOrder[] calldata orders) external nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _handleResolvedOrders(resolvedOrders);
    }

    function _handleResolvedOrders(ResolvedRelayOrder[] memory orders) private {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory order = orders[i];
                order.transferInputTokens(permit2);
                executeActions(order.actions);
                emit Fill(order.hash, msg.sender, order.swapper, order.permit.nonce);
            }
        }
    }

    function resolve(SignedOrder memory signedOrder) internal view returns (ResolvedRelayOrder memory resolvedOrder) {
        // Validate the order before resolving.
        RelayOrder memory order = abi.decode(signedOrder.order, (RelayOrder));
        order.validate();

        return ResolvedRelayOrder({
            swapper: order.info.swapper,
            actions: order.actions,
            permit: order.toPermit(),
            details: order.toTransferDetails(),
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    function executeActions(bytes[] memory actions) internal {
        uint256 actionsLength = actions.length;
        for (uint256 i = 0; i < actionsLength;) {
            (bool success, bytes memory result) = universalRouter.call(actions[i]);
            if (!success) {
                // bubble up all errors, including custom errors which are encoded like functions
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            unchecked {
                i++;
            }
        }
    }
}
