// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ResolvedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedRelayOrder, InputTokenWithRecipient} from "../base/ReactorStructs.sol";

/// @notice handling some permit2-specific encoding
library Permit2Lib {
    /// @notice returns a ResolvedOrder into a permit object
    function toPermit(ResolvedRelayOrder memory order)
        internal
        view
        returns (ISignatureTransfer.PermitBatchTransferFrom memory)
    {
        InputTokenWithRecipient[] memory inputsRequired = getPositiveInputs(order.inputs);
        ISignatureTransfer.TokenPermissions[] memory permissions =
            new ISignatureTransfer.TokenPermissions[](inputsRequired.length);

        for (uint256 i = 0; i < inputsRequired.length; i++) {
            permissions[i] = ISignatureTransfer.TokenPermissions({
                token: address(inputsRequired[i].token),
                amount: uint256(inputsRequired[i].amount) // safe to cast here because we check above
            });
        }
        return ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permissions,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    /// @notice returns a ResolvedOrder into a permit object
    function transferDetails(ResolvedRelayOrder memory order)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory)
    {
        InputTokenWithRecipient[] memory inputsRequired = getPositiveInputs(order.inputs);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](inputsRequired.length);
        for (uint256 i = 0; i < inputsRequired.length; i++) {
            // if recipient is 0x0, use msg.sender
            address recipient = inputsRequired[i].recipient == address(0) ? msg.sender : inputsRequired[i].recipient;
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: recipient,
                requestedAmount: uint256(inputsRequired[i].amount) // safe to cast here because we check above
            });
        }
        return details;
    }

    function getPositiveInputs(InputTokenWithRecipient[] memory inputs)
        internal
        view
        returns (InputTokenWithRecipient[] memory)
    {
        InputTokenWithRecipient[] memory positiveInputs;
        for (uint256 i = 0; i < inputs.length; i++) {
            if (inputs[i].amount > 0) {
                positiveInputs[i] = inputs[i];
            }
        }
        return positiveInputs;
    }
}
