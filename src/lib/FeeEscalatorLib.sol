// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {FeeEscalator} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

library FeeEscalatorLib {
    using FixedPointMathLib for uint256;

    /// @notice calculates an amount on a linear curve over time from startTime to endTime
    /// @dev handles only increasing amounts from startAmount to endAmount
    /// @param startAmount The amount of tokens at startTime
    /// @param endAmount The amount of tokens at endTime
    /// @param startTime The time to start escalating linearly
    /// @param endTime The time to stop escalating linearly
    function resolve(uint256 startAmount, uint256 endAmount, uint256 startTime, uint256 endTime)
        internal
        view
        returns (uint256 resolvedAmount)
    {
        if (startAmount > endAmount) {
            revert ReactorErrors.InvalidAmounts();
        } else if (endTime < startTime) {
            revert ReactorErrors.EndTimeBeforeStartTime();
        } else if (endTime <= block.timestamp) {
            resolvedAmount = endAmount;
        } else if (startTime >= block.timestamp) {
            resolvedAmount = startAmount;
        } else {
            unchecked {
                uint256 elapsed = block.timestamp - startTime;
                uint256 duration = endTime - startTime;
                resolvedAmount = startAmount + (endAmount - startAmount).mulDivDown(elapsed, duration);
            }
        }
    }

    /// @notice Transforms the fee data into a TokenPermissions struct needed for the permit call.
    /// @dev the amount signed in the token permissions must be the endAmount of the fee
    function toTokenPermissions(FeeEscalator memory fee)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions memory permission)
    {
        permission = ISignatureTransfer.TokenPermissions({token: fee.token, amount: fee.endAmount});
    }

    /// @notice Transforms the fee data into the the resolved amount and the provided recipient.
    function toTransferDetails(FeeEscalator memory fee, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory detail)
    {
        uint256 resolvedAmount = resolve(fee.startAmount, fee.endAmount, fee.startTime, fee.endTime);
        // if the fee.recipient is not set, use the passed in feeRecipient
        detail = ISignatureTransfer.SignatureTransferDetails({
            to: fee.recipient == address(0) ? feeRecipient : fee.recipient,
            requestedAmount: resolvedAmount
        });
    }
}
