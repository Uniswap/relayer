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
        uint256 inputLength = order.inputs.length;
        // Build TokenPermissions array with the maxValue
        ISignatureTransfer.TokenPermissions[] memory permissions = new ISignatureTransfer.TokenPermissions[](
            inputLength
        );

        for (uint256 i = 0; i < inputLength; i++) {
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
        uint256 inputLength = order.inputs.length;
        // Build TransferDetails with the final resolved amount
        details = new ISignatureTransfer.SignatureTransferDetails[](inputLength);

        for (uint256 i = 0; i < inputLength; i++) {
            Input memory input = order.inputs[i];
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: input.recipient,
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
        uint256 inputLength = order.inputs.length;
        // Build an array for the startAmounts and recipients.
        uint256[] memory startAmounts = new uint256[](inputLength);
        address[] memory recipients = new address[](inputLength);

        for (uint256 i = 0; i < inputLength; i++) {
            Input memory input = order.inputs[i];
            startAmounts[i] = input.startAmount;
            recipients[i] = input.recipient;
        }

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
