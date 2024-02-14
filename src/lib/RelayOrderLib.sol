// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {RelayOrder, Input, FeeEscalator} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";
import {FeeEscalatorLib} from "./FeeEscalatorLib.sol";

library RelayOrderLib {
    using RelayOrderLib for RelayOrder;
    using FeeEscalatorLib for FeeEscalator;

    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked("RelayOrder witness)", RELAY_ORDER_TYPESTRING, PermitHash._TOKEN_PERMISSIONS_TYPESTRING)
    );

    /// @dev input token addresses are signed in the token permissions of the permit information.
    bytes internal constant RELAY_ORDER_TYPESTRING = abi.encodePacked(
        "RelayOrder(",
        "address reactor,",
        "address swapper,",
        "address inputRecipient,",
        "uint256 feeStartAmount,",
        "uint256 feeStartTime,",
        "uint256 feeEndTime,",
        "address feeRecipient,",
        "bytes actions)"
    );

    bytes32 internal constant RELAY_ORDER_TYPEHASH = keccak256(RELAY_ORDER_TYPESTRING);

    /// @notice validate a relay order
    function validate(RelayOrder memory order) internal view {
        if (order.info.deadline < order.fee.endTime) {
            revert ReactorErrors.DeadlineBeforeEndTime();
        }

        if (address(this) != address(order.info.reactor)) {
            revert ReactorErrors.InvalidReactor();
        }
    }

    /// @notice get the permissions necessary for the permit call
    function toTokenPermissions(RelayOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions[] memory permissions)
    {
        permissions = new ISignatureTransfer.TokenPermissions[](2);
        permissions[0] = ISignatureTransfer.TokenPermissions({token: order.input.token, amount: order.input.amount});
        permissions[1] = order.fee.toTokenPermissions();
    }

    /// @notice get the transfer details needed for the permit call
    /// @param feeRecipient the address to receive any specified fee
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

    /// @notice transfer all input tokens and the fee to their respective recipients
    /// @dev resolves the fee amount on the curve specified in the order
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

    /// @notice hash the given order
    /// @param order the order to hash
    /// @dev we only hash fields not included in the permit already (excluding token addresses and maxAmounts)
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RELAY_ORDER_TYPEHASH,
                order.info.reactor,
                order.info.swapper,
                order.input.recipient,
                order.fee.startAmount,
                order.fee.startTime,
                order.fee.endTime,
                order.fee.recipient,
                keccak256(order.actions)
            )
        );
    }
}
