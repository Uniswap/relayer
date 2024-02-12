// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Input} from "../base/ReactorStructs.sol";
import {FeeEscalator, Input} from "../base/ReactorStructs.sol";

library FeeEscalatorLib {
    using FixedPointMathLib for uint256;

    string public constant FEE_ESCALATOR_TYPESTRING =
        "FeeEscalator(address token,uint256 startAmount,uint256 endAmount,uint256 startTime,uint256 endTime)";
    bytes32 internal constant FEE_ESCALATOR_TYPEHASH =
        keccak256("FeeEscalator(address token,uint256 startAmount,uint256 endAmount,uint256 startTime,uint256 endTime)");

    /// @notice thrown if the escalation direction is incorrect
    error InvalidAmounts();
    error EndTimeBeforeStartTime();

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
            revert InvalidAmounts();
        } else if (endTime < startTime) {
            revert EndTimeBeforeStartTime();
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
    function toTokenPermissions(FeeEscalator memory fee)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions memory permission)
    {
        permission = ISignatureTransfer.TokenPermissions({token: fee.token, amount: fee.endAmount});
    }

    /// @notice Handles transforming the fee data into the the resolved amounts and respective recipients.
    function toTransferDetails(FeeEscalator memory fee, address feeRecipient)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory details)
    {
        uint256 resolvedAmount = resolve(fee.startAmount, fee.endAmount, fee.startTime, fee.endTime);
        details = ISignatureTransfer.SignatureTransferDetails({to: feeRecipient, requestedAmount: resolvedAmount});
    }

    /// @notice hash the fee
    /// @return the eip-712 order hash
    function hash(FeeEscalator memory fee) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(FEE_ESCALATOR_TYPEHASH, fee.token, fee.startAmount, fee.endAmount, fee.startTime, fee.endTime)
        );
    }
}
