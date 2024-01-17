// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayDecayLib} from "./RelayDecayLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayOrder, Input} from "../base/ReactorStructs.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

library RelayOrderLib {
    using RelayOrderLib for RelayOrder;

    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked("RelayOrder witness)", RELAY_ORDER_TYPESTRING, PermitHash._TOKEN_PERMISSIONS_TYPESTRING)
    );

    bytes internal constant RELAY_ORDER_TYPESTRING = abi.encodePacked(
        "RelayOrder(",
        "address reactor,",
        "address swapper,",
        "uint256[] startAmounts,",
        "address[] recipients,",
        "uint256 decayStartTime,",
        "uint256 decayEndTime,",
        "bytes[] actions)"
    );

    bytes32 internal constant RELAY_ORDER_TYPEHASH = keccak256(RELAY_ORDER_TYPESTRING);

    function validate(RelayOrder memory order) internal view {
        if (order.info.deadline < order.decayEndTime) {
            revert ReactorErrors.DeadlineBeforeEndTime();
        }

        if (block.timestamp > order.info.deadline) {
            revert ReactorErrors.DeadlinePassed();
        }

        if (order.decayEndTime < order.decayStartTime) {
            revert ReactorErrors.OrderEndTimeBeforeStartTime();
        }

        if (address(this) != address(order.info.reactor)) {
            revert ReactorErrors.InvalidReactor();
        }
    }

    function toPermit(RelayOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.PermitBatchTransferFrom memory permit)
    {
        uint256 inputsLength = order.inputs.length;
        // Build TokenPermissions array with the maxValue
        ISignatureTransfer.TokenPermissions[] memory permissions =
            new ISignatureTransfer.TokenPermissions[](inputsLength);

        for (uint256 i = 0; i < inputsLength; i++) {
            Input memory input = order.inputs[i];
            permissions[i] = ISignatureTransfer.TokenPermissions({token: input.token, amount: input.maxAmount});
        }

        return ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permissions,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    /// @notice The requestedAmount is built from the decayed/resolved amount.
    function toTransferDetails(RelayOrder memory order)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        uint256 inputsLength = order.inputs.length;
        // Build TransferDetails with the final resolved amount
        details = new ISignatureTransfer.SignatureTransferDetails[](inputsLength);

        for (uint256 i = 0; i < inputsLength; i++) {
            Input memory input = order.inputs[i];
            address recipient = input.recipient == address(0) ? msg.sender : input.recipient;
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: recipient,
                requestedAmount: RelayDecayLib.decay(
                    input.startAmount, input.maxAmount, order.decayStartTime, order.decayEndTime
                    )
            });
        }

        return details;
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @dev We do not hash the entire Input struct as only some of the input information is required in the witness (recipients, and startAmounts). The token and maxAmount are already hashed in the TokenPermissions struct of the permit.
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        uint256 inputsLength = order.inputs.length;
        // Build an array for the startAmounts and recipients.
        uint256[] memory startAmounts = new uint256[](inputsLength);
        address[] memory recipients = new address[](inputsLength);

        for (uint256 i = 0; i < inputsLength; i++) {
            Input memory input = order.inputs[i];
            startAmounts[i] = input.startAmount;
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
                keccak256(abi.encodePacked(startAmounts)),
                keccak256(abi.encodePacked(recipients)),
                order.decayStartTime,
                order.decayEndTime,
                abi.encodePacked(hashedActions)
            )
        );
    }
}
