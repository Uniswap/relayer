// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {FeeEscalator} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

/// @notice Handles the EIP712 defined typehash and hashing for FeeEscalator, and performs escalation calculations
library FeeEscalatorLib {
    using FixedPointMathLib for uint256;

    bytes internal constant FEE_ESCALATOR_TYPESTRING = abi.encodePacked(
        "FeeEscalator(",
        "address token,",
        "uint256 startAmount,",
        "uint256 endAmount,",
        "uint256 startTime,",
        "uint256 endTime)"
    );

    bytes32 internal constant FEE_ESCALATOR_TYPEHASH = keccak256(FEE_ESCALATOR_TYPESTRING);

    /// @notice Calculates an amount on a linear curve over time from startTime to endTime
    /// @dev Handles only increasing amounts from startAmount to endAmount
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
    /// @dev The amount signed in the token permissions must be the endAmount of the fee
    /// @param fee The order fee
    function toTokenPermissions(FeeEscalator memory fee)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions memory permission)
    {
        permission = ISignatureTransfer.TokenPermissions({token: fee.token, amount: fee.endAmount});
    }

    /// @notice Transforms the fee data into a SignatureTransferDetails struct needed for the permit call.
    /// @dev The recipient is the fee.recipient if set, otherwise the caller provided feeRecipient
    /// @param fee The order fee
    /// @param feeRecipient the address to receive any specified fee
    function toTransferDetails(FeeEscalator memory fee, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory detail)
    {
        // resolve resolvedAmount based on the current time and to based on feeRecipient
        uint256 resolvedAmount = resolve(fee.startAmount, fee.endAmount, fee.startTime, fee.endTime);
        detail = ISignatureTransfer.SignatureTransferDetails({to: feeRecipient, requestedAmount: resolvedAmount});
    }

    /// @notice Hashes the fee
    /// @param fee The fee to hash
    /// @return The hash of the fee
    function hash(FeeEscalator memory fee) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(FEE_ESCALATOR_TYPEHASH, fee.token, fee.startAmount, fee.endAmount, fee.startTime, fee.endTime)
        );
    }
}
