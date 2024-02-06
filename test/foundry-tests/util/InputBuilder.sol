// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;

import {Input} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ONE} from "./Constants.sol";

library InputBuilder {
    function init(ERC20 token) internal pure returns (Input memory) {
        // The default input does not decay, so the start and end amounts are the same.
        return Input({token: address(token), recipient: address(0), startAmount: ONE, maxAmount: ONE});
    }

    function withRecipient(Input memory input, address _recipient) internal pure returns (Input memory) {
        input.recipient = _recipient;
        return input;
    }

    function withStartAmount(Input memory input, uint256 _startAmount) internal pure returns (Input memory) {
        input.startAmount = _startAmount;
        return input;
    }

    function withMaxAmount(Input memory input, uint256 _maxAmount) internal pure returns (Input memory) {
        input.maxAmount = _maxAmount;
        return input;
    }
}
