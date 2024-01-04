// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";

/// @dev tokens that need to be sent from the swapper in order to satisfy an order
struct InputTokenWithRecipient {
    ERC20 token;
    uint256 amount;
    // Needed for dutch decaying inputs
    uint256 maxAmount;
    address recipient;
}

/// @dev tokens that need to be received by the recipient in order to satisfy an order
struct OutputToken {
    address token;
    uint256 amount;
    address recipient;
}

struct ResolvedRelayOrder {
    OrderInfo info;
    bytes[] actions;
    InputTokenWithRecipient[] inputs;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash;
}
