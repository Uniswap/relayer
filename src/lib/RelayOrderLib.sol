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
        abi.encodePacked(
            "RelayOrder witness)",
            FeeEscalatorLib.FEE_ESCALATOR_TYPESTRING,
            RELAY_ORDER_TYPESTRING,
            PermitHash._TOKEN_PERMISSIONS_TYPESTRING
        )
    );

    /// @dev input token addresses are signed in the token permissions of the permit information.
    bytes internal constant RELAY_ORDER_TYPESTRING = abi.encodePacked(
        "RelayOrder(",
        "address reactor,",
        "address swapper,",
        "uint256[] amounts,",
        "address[] recipients,",
        "FeeEscalator fee,",
        "bytes[] actions)"
    );

    bytes32 internal constant RELAY_ORDER_TYPEHASH = keccak256(RELAY_ORDER_TYPESTRING);

    function validate(RelayOrder memory order) internal view {
        if (order.info.deadline < order.fee.endTime) {
            revert ReactorErrors.DeadlineBeforeEndTime();
        }

        if (order.fee.endTime < order.fee.startTime) {
            revert ReactorErrors.EndTimeBeforeStartTime();
        }

        if (address(this) != address(order.info.reactor)) {
            revert ReactorErrors.InvalidReactor();
        }
    }

    /// @notice get the permissions necessary for the permit call
    function toPermit(RelayOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions[] memory permissions)
    {
        // add one for fee escalator
        uint256 numPermissions = order.inputs.length + 1;
        permissions = new ISignatureTransfer.TokenPermissions[](numPermissions);

        for (uint256 i = 0; i < order.inputs.length; i++) {
            permissions[i] =
                ISignatureTransfer.TokenPermissions({token: order.inputs[i].token, amount: order.inputs[i].amount});
        }
        permissions[numPermissions - 1] = order.fee.toPermit();
    }

    /// @notice get the transfer details needed for the permit call
    /// @param order 
    /// @param feeRecipient the address to receive any specified fee
    function toTransferDetails(RelayOrder memory order, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        // add one for fee escalator
        uint256 numPermissions = order.inputs.length + 1;
        details = new ISignatureTransfer.SignatureTransferDetails[](numPermissions);

        for (uint256 i = 0; i < order.inputs.length; i++) {
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: order.inputs[i].recipient,
                requestedAmount: order.inputs[i].amount
            });
        }
        details[numPermissions - 1] = order.fee.toTransferDetails(feeRecipient);
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
        ISignatureTransfer.TokenPermissions[] memory permissions = order.toPermit();
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
    /// @dev We do not hash the entire Input struct as only some of the input information is required in the witness (recipients, and amounts). The token and maxAmount are already hashed in the TokenPermissions struct of the permit.
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        uint256 inputsLength = order.inputs.length;
        // Build an array for the input amounts and recipients.
        uint256[] memory amounts = new uint256[](inputsLength);
        address[] memory recipients = new address[](inputsLength);

        for (uint256 i = 0; i < inputsLength; i++) {
            Input memory input = order.inputs[i];
            amounts[i] = input.amount;
            recipients[i] = input.recipient;
        }

        // Bytes[] must be hashed individually then concatenated according to EIP712.
        uint256 actionsLength = order.actions.length;
        bytes32[] memory hashedActions = new bytes32[](actionsLength);
        for (uint256 i = 0; i < actionsLength; i++) {
            hashedActions[i] = keccak256(order.actions[i]);
        }

        return keccak256(
            abi.encode(
                RELAY_ORDER_TYPEHASH,
                order.info.reactor,
                order.info.swapper,
                keccak256(abi.encodePacked(amounts)),
                keccak256(abi.encodePacked(recipients)),
                order.fee.hash(),
                keccak256(abi.encodePacked(hashedActions))
            )
        );
    }
}
