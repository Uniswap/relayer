// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayDecayLib} from "./RelayDecayLib.sol";

/// @notice Handles transforming the input data into the permissions on permit2 and the decayed amounts for the transfer details.
library InputsLib {
    function toPermitDetails(Input[] memory inputs, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (
            ISignatureTransfer.TokenPermissions[] memory permissions,
            ISignatureTransfer.SignatureTransferDetails[] memory details
        )
    {
        permissions = new ISignatureTransfer.TokenPermissions[](inputs.length);
        details = new ISignatureTransfer.SignatureTransferDetails[](inputs.length);

        for (uint256 i = 0; i < inputs.length; i++) {
            Input memory input = inputs[i];
            permissions[i] = ISignatureTransfer.TokenPermissions({token: input.token, amount: input.maxAmount});

            address recipient = input.recipient == address(0) ? msg.sender : input.recipient;
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: recipient,
                requestedAmount: RelayDecayLib.decay(input.startAmount, input.maxAmount, decayStartTime, decayEndTime)
            });
        }
    }
}
