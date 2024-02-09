// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Input} from "../base/ReactorStructs.sol";
import {RelayDecayLib} from "./RelayDecayLib.sol";
import {FeeEscalator, Input} from "../base/ReactorStructs.sol";

library FeeEscalatorLib {
    string public constant FEE_ESCALATOR_TYPESTRING = "FeeEscalator(address token,uint256 startAmount,uint256 maxAmount,uint256 startTime,uint256 endTime)";
    bytes32 internal constant FEE_ESCALATOR_TYPEHASH = keccak256("FeeEscalator(address token,uint256 startAmount,uint256 maxAmount,uint256 startTime,uint256 endTime)");

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
        details = ISignatureTransfer.SignatureTransferDetails({to: feeRecipient, requestedAmount: decayedAmount});
    }

    /// @notice hash the fee
    /// @return the eip-712 order hash
    function hash(FeeEscalator memory fee) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FEE_ESCALATOR_TYPEHASH,
                fee.token,
                fee.startAmount,
                fee.maxAmount,
                fee.startTime,
                fee.endTime
            )
        );
    }
}
