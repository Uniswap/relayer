// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {RelayOrder, FeeEscalator, Input, OrderInfo} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {FeeEscalatorLib} from "./FeeEscalatorLib.sol";
import {InputLib} from "./InputLib.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";

library RelayOrderLib {
    using RelayOrderLib for RelayOrder;
    using FeeEscalatorLib for FeeEscalator;
    using OrderInfoLib for OrderInfo;
    using InputLib for Input;

    // EIP712 notes that nested structs should be ordered alphabetically.
    // With our added RelayOrder witness, the top level type becomes
    // "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,RelayOrder witness)"
    // Meaning we order the nested structs as follows:
    // FeeEscalator, Input, OrderInfo, RelayOrder, TokenPermissions
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "RelayOrder witness)",
            FeeEscalatorLib.FEE_ESCALATOR_TYPESTRING,
            InputLib.INPUT_TYPESTRING,
            OrderInfoLib.ORDER_INFO_TYPESTRING,
            RelayOrderLib.TOPLEVEL_RELAY_ORDER_TYPESTRING,
            PermitHash._TOKEN_PERMISSIONS_TYPESTRING
        )
    );

    bytes internal constant TOPLEVEL_RELAY_ORDER_TYPESTRING = abi.encodePacked(
        "RelayOrder(", "OrderInfo info,", "Input input,", "FeeEscalator fee,", "bytes universalRouterCalldata)"
    );

    // EIP712 notes that nested structs should be ordered alphabetically:
    // FeeEscalator, Input, OrderInfo
    bytes internal constant FULL_RELAY_ORDER_TYPESTRING = abi.encodePacked(
        RelayOrderLib.TOPLEVEL_RELAY_ORDER_TYPESTRING,
        FeeEscalatorLib.FEE_ESCALATOR_TYPESTRING,
        InputLib.INPUT_TYPESTRING,
        OrderInfoLib.ORDER_INFO_TYPESTRING
    );

    bytes32 internal constant FULL_RELAY_ORDER_TYPEHASH = keccak256(FULL_RELAY_ORDER_TYPESTRING);

    /// @notice Validate a relay order
    function validate(RelayOrder memory order) internal view {
        if (order.info.deadline < order.fee.endTime) {
            revert ReactorErrors.DeadlineBeforeEndTime();
        }

        if (address(this) != address(order.info.reactor)) {
            revert ReactorErrors.InvalidReactor();
        }
    }

    /// @notice Get the permissions necessary for the permit call
    function toTokenPermissions(RelayOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions[] memory permissions)
    {
        permissions = new ISignatureTransfer.TokenPermissions[](2);
        permissions[0] = ISignatureTransfer.TokenPermissions({token: order.input.token, amount: order.input.amount});
        permissions[1] = order.fee.toTokenPermissions();
    }

    /// @notice Get the transfer details needed for the permit call
    /// @param feeRecipient The address to receive any specified fee
    function toTransferDetails(RelayOrder memory order, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        details = new ISignatureTransfer.SignatureTransferDetails[](2);
        details[0] = ISignatureTransfer.SignatureTransferDetails({
            to: order.input.recipient,
            requestedAmount: order.input.amount
        });
        details[1] = order.fee.toTransferDetails(feeRecipient);
    }

    /// @notice Transfer all input tokens and the fee to their respective recipients
    /// @dev Resolves the fee amount on the curve specified in the order
    function transferInputTokens(
        RelayOrder memory order,
        bytes32 orderHash,
        IPermit2 permit2,
        address feeRecipient,
        bytes calldata sig
    ) internal {
        ISignatureTransfer.TokenPermissions[] memory permissions = order.toTokenPermissions();
        ISignatureTransfer.SignatureTransferDetails[] memory details = order.toTransferDetails(feeRecipient);

        permit2.permitWitnessTransferFrom(
            ISignatureTransfer.PermitBatchTransferFrom({
                permitted: permissions,
                nonce: order.info.nonce,
                deadline: order.info.deadline
            }),
            details,
            order.info.swapper,
            orderHash,
            RelayOrderLib.PERMIT2_ORDER_TYPE,
            sig
        );
    }

    /// @notice hash The given order
    /// @param order The order to hash
    /// @return The eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FULL_RELAY_ORDER_TYPEHASH,
                order.info.hash(),
                order.input.hash(),
                order.fee.hash(),
                keccak256(order.universalRouterCalldata)
            )
        );
    }
}
