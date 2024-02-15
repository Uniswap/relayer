// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrder} from "../../../../src/base/ReactorStructs.sol";
import {RelayOrderLib} from "../../../../src/lib/RelayOrderLib.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

contract MockReactor {
    function validate(RelayOrder memory order) public view {
        RelayOrderLib.validate(order);
    }

    function transferInputTokens(
        RelayOrder memory order,
        bytes32 orderHash,
        IPermit2 permit2,
        address feeRecipient,
        bytes calldata sig
    ) external {
        RelayOrderLib.transferInputTokens(order, orderHash, permit2, feeRecipient, sig);
    }
}
