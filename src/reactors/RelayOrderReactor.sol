// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";
import {ReactorEvents} from "UniswapX/src/base/ReactorEvents.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";
import {RelayOrder} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {Multicall} from "../base/Multicall.sol";
import {RelayOrderLib} from "../lib/RelayOrderLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";

/// @notice Reactor for handling the execution of RelayOrders
/// @notice This contract MUST NOT have approvals or priviledged access
/// @notice any funds in this contract can be swept away by anyone
contract RelayOrderReactor is Multicall, ReactorEvents, ReactorErrors, IRelayOrderReactor {
    using RelayOrderLib for RelayOrder;

    /// @notice Permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;
    /// @notice Actions only execute on the universal router.
    address public immutable universalRouter;

    constructor(IPermit2 _permit2, address _universalRouter) {
        permit2 = _permit2;
        universalRouter = _universalRouter;
    }

    /// @inheritdoc IRelayOrderReactor
    function execute(SignedOrder calldata signedOrder, address feeRecipient) external {
        (RelayOrder memory order) = abi.decode(signedOrder.order, (RelayOrder));
        order.validate();

        bytes32 orderHash = order.hash();
        order.transferInputTokens(orderHash, permit2, feeRecipient, signedOrder.sig);

        (bool success, bytes memory result) = universalRouter.call(order.actions);
        if (!success) {
            // bubble up all errors, including custom errors which are encoded like functions
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        emit Fill(orderHash, msg.sender, order.info.swapper, order.info.nonce);
    }

    /// @inheritdoc IRelayOrderReactor
    function permit(ERC20 token, bytes calldata data) external {
        (address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        Permit2Lib.permit2(token, _owner, spender, value, deadline, v, r, s);
    }
}
