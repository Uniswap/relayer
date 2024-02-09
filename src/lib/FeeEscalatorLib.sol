// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Input} from "../base/ReactorStructs.sol";
import {RelayDecayLib} from "./RelayDecayLib.sol";
import {FeeEscalator, Input} from "../base/ReactorStructs.sol";

library FeeEscalatorLib {
    /// @notice Transforms the input data into the TokenPermissions struct needed for the permit call.
    function toPermit(FeeEscalator memory fee)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions[] memory permissions)
    {
        permissions = new ISignatureTransfer.TokenPermissions[](1);
        permissions[0] = ISignatureTransfer.TokenPermissions({token: fee.token, amount: fee.maxAmount});
    }
    /// @notice Handles transforming the input data into the the decayed amounts and respective recipients.
    function toTransferDetails(FeeEscalator memory fee, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory details)
    {
        uint256 decayedAmount = RelayDecayLib.decay(fee.startAmount, fee.maxAmount, fee.startTime, fee.endTime);
        details = ISignatureTransfer.SignatureTransferDetails({
                to: feeRecipient,
                requestedAmount: decayedAmount
        });
    }
} 