// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {ResolvedRelayOrder, RelayOrder} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {RelayOrderLib} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";

import "forge-std/console2.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is ReactorEvents, ReactorErrors, ReentrancyGuard, IRelayOrderReactor {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    /// @notice permit2 address used for token transfers and signature verification

    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
    }

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

    function _handleResolvedOrders(ResolvedRelayOrder[] memory orders) private {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedRelayOrder memory order = orders[i];
                order.transferInputTokens(permit2);
                order.executeActions(); // passing the whole order in? would be nice to not pass all the extra unrelated info in
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

    receive() external payable {
        // receive native asset to support native output
    }
}
