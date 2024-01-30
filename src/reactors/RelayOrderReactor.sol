// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {ResolvedRelayOrder, RelayOrder} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {Multicall} from "../base/Multicall.sol";
import {RelayOrderLib} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is Multicall, ReactorEvents, ReactorErrors, IRelayOrderReactor {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;
    /// @notice permit2 address used for token transfers and signature verification

    IPermit2 public immutable permit2;
    address public immutable universalRouter;

    constructor(IPermit2 _permit2, address _universalRouter) {
        permit2 = _permit2;
        universalRouter = _universalRouter;
    }

    /// @notice execute a signed RelayOrder
    function execute(SignedOrder calldata order) external {
        ResolvedRelayOrder memory resolvedOrder = resolve(order);

        resolvedOrder.transferInputTokens(permit2);
        executeActions(resolvedOrder.actions);
        emit Fill(resolvedOrder.hash, msg.sender, resolvedOrder.swapper, resolvedOrder.permit.nonce);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    /// must be called before the call to the reactor
    function permit(ERC20 token, bytes calldata data) external {
        (address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        Permit2Lib.permit2(token, _owner, spender, value, deadline, v, r, s);
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
