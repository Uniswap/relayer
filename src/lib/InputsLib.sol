// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Input} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayDecayLib} from "./RelayDecayLib.sol";

///@notice Performs the decay on input data and transforms info into necessary structs required for the permit call.
library InputsLib {
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

    /// @notice Transforms and decays the Input into the ISignatureTransfer.SignatureTransferDetails format needed for the permit call.
    function toTransferDetails(
        Input[] memory inputs,
        address feeRecipient,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) internal view returns (ISignatureTransfer.SignatureTransferDetails[] memory details) {
        details = new ISignatureTransfer.SignatureTransferDetails[](inputs.length);

        for (uint256 i = 0; i < inputs.length; i++) {
            Input memory input = inputs[i];
            address recipient = input.recipient == address(0) ? feeRecipient : input.recipient;
            uint256 decayedAmount =
                RelayDecayLib.decay(input.startAmount, input.maxAmount, decayStartTime, decayEndTime);
            details[i] = ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: decayedAmount});
        }
    }
}
