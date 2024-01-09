// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayDecayLib} from "./RelayDecayLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayOrder} from "../base/ReactorStructs.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

import "forge-std/console2.sol";

library RelayOrderLib {
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
        if (
            order.startAmounts.length != order.recipients.length
                || order.startAmounts.length != order.permit.permitted.length
        ) revert ReactorErrors.LengthMismatch();

        if (order.permit.deadline < order.decayEndTime) {
            revert ReactorErrors.DeadlineBeforeEndTime();
        }

        if (block.timestamp > order.permit.deadline) {
            revert ReactorErrors.DeadlinePassed();
        }

        if (order.decayEndTime < order.decayStartTime) {
            revert ReactorErrors.OrderEndTimeBeforeStartTime();
        }

        if (address(this) != address(order.reactor)) {
            revert ReactorErrors.InvalidReactor();
        }
    }

    /// @notice Resolving the order happens as we get the final transfer details. Otherwise, we would iterate through all the resolved amounts again.
    function transferDetails(RelayOrder memory order)
        internal
        returns (ISignatureTransfer.SignatureTransferDetails[] memory details)
    {
        uint256 detailsLength = order.permit.permitted.length;

        details = new ISignatureTransfer.SignatureTransferDetails[](detailsLength);

        for (uint256 i = 0; i < detailsLength; i++) {
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: order.recipients[i],
                requestedAmount: RelayDecayLib.decay(
                    order.startAmounts[i],
                    order.permit.permitted[i].amount,
                    order.decayStartTime, // TODO: optimization, wasteful to pass this in everytime.. can we rewrite decay?
                    order.decayEndTime
                    )
            });
        }
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @dev the permit field in the RelayOrder is not included in the witness hash because it is already signed over
    /// @return the eip-712 order hash
    function hash(RelayOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RELAY_ORDER_TYPEHASH,
                order.reactor,
                order.swapper,
                keccak256(abi.encodePacked(order.startAmounts)), // I belive the EIP721 standard is encodePacked
                keccak256(abi.encodePacked(order.recipients)),
                order.decayStartTime,
                order.decayEndTime,
                order.actions // for bytes array you dont have to encodePacked? double check
            )
        );
    }
}
