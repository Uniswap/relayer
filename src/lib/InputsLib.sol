// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayDecayLib} from "./RelayDecayLib.sol";
import {ResolvedInput} from "../base/ReactorStructs.sol";

///@notice Performs the decay on input data and transforms info into necessary structs required for the permit call.
library InputsLib {
    /// @notice Handles transforming the input data into the the decayed amounts and respective recipients.
    function toResolvedInputs(Input[] memory inputs, uint256 decayStartTime, uint256 decayEndTime, address feeRecipient)
        internal
        view
        returns (ResolvedInput[] memory resolvedInputs)
    {
        resolvedInputs = new ResolvedInput[](inputs.length);

        for (uint256 i = 0; i < inputs.length; i++) {
            Input memory input = inputs[i];
            address recipient = input.recipient == address(0) ? feeRecipient : input.recipient;
            uint256 decayedAmount =
                RelayDecayLib.decay(input.startAmount, input.maxAmount, decayStartTime, decayEndTime);
            resolvedInputs[i] = ResolvedInput({token: input.token, recipient: recipient, amount: decayedAmount});
        }
    }

    /// @notice Transforms the input data into the TokenPermissions struct needed for the permit call.
    function toPermit(Input[] memory inputs)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions[] memory permissions)
    {
        permissions = new ISignatureTransfer.TokenPermissions[](inputs.length);

        for (uint256 i = 0; i < inputs.length; i++) {
            Input memory input = inputs[i];
            permissions[i] = ISignatureTransfer.TokenPermissions({token: input.token, amount: input.maxAmount});
        }
    }

    /// @notice Transforms the ResolvedInput into the ISignatureTransfer.SignatureTransferDetails format needed for the permit call.
    function toTransferDetails(ResolvedInput[] memory resolvedInputs)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        details = new ISignatureTransfer.SignatureTransferDetails[](resolvedInputs.length);

        for (uint256 i = 0; i < resolvedInputs.length; i++) {
            ResolvedInput memory resolvedInput = resolvedInputs[i];
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: resolvedInput.recipient,
                requestedAmount: resolvedInput.amount
            });
        }
    }
}
