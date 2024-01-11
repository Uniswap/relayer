// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayDecayLib} from "./RelayDecayLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayOrder, Input} from "../base/ReactorStructs.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

import "forge-std/console2.sol";

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

    function validate(RelayOrder memory order) internal {
        // if (
        //     order.startAmounts.length != order.recipients.length
        //         || order.startAmounts.length != order.permit.permitted.length
        // ) revert ReactorErrors.LengthMismatch();

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

    /// @notice Transforms data from the RelayOrder type into necessary structs and arrays needed for the permit2 call and the order hash.
    /// @notice PermitBatchTransferFrom data is reconstructed from token and maxAmount details in the input
    /// @notice TransferDetails data is reconstructed from decaying the order.inputs
    /// @notice The order hash is reconstructed by constructing the amounts and recipients into standalone arrays
    /// @return The permit information as PermitBatchTransferFrom from the token and maxAmount details
    /// @return The transfer details, using the resolved input amount calculated from the decay
    /// @return The order hash
    function transformAndDecay(RelayOrder memory order)
        internal
        returns (
            ISignatureTransfer.PermitBatchTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails[] memory details,
            bytes32 orderHash
        )
    {
        uint256 inputLength = order.inputs.length;
        // Build TokenPermissions array with the maxValue
        ISignatureTransfer.TokenPermissions[] memory permissions = new ISignatureTransfer.TokenPermissions[](
            inputLength
        );
        // Build TransferDetails with the final resolved amount
        details = new ISignatureTransfer.SignatureTransferDetails[](
            inputLength
        );

        // Build array of startAmounts, needed to properly hash the witness.
        uint256[] memory startAmounts = new uint256[](inputLength);

        // Build array of recipients, needed to properly hash witness.
        address[] memory recipients = new address[](inputLength);

        for (uint256 i = 0; i < inputLength; i++) {
            Input memory input = order.inputs[i];
            permissions[i] = ISignatureTransfer.TokenPermissions({token: input.token, amount: input.maxAmount});
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: input.recipient,
                requestedAmount: RelayDecayLib.decay(
                    input.startAmount, input.maxAmount, order.decayStartTime, order.decayEndTime
                    )
            });
            startAmounts[i] = input.startAmount;
            recipients[i] = input.recipient;
        }

        permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permissions,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });

        orderHash = order.hash(startAmounts, recipients);

        return (permit, details, orderHash);
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @dev the permit field in the RelayOrder is not included in the witness hash because it is already signed over
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order, uint256[] memory startAmounts, address[] memory recipients)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                RELAY_ORDER_TYPEHASH,
                order.info.reactor,
                order.info.swapper,
                keccak256(abi.encodePacked(startAmounts)), // I belive the EIP721 standard is encodePacked
                keccak256(abi.encodePacked(recipients)),
                order.decayStartTime,
                order.decayEndTime,
                order.actions // for bytes array you dont have to encodePacked? double check
            )
        );
    }
}
