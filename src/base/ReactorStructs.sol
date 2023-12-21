// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OrderInfo, OutputToken} from "UniswapX/src/base/ReactorStructs.sol";

/// @dev tokens that need to be sent from the swapper in order to satisfy an order
struct InputTokenWithRecipient {
    ERC20 token;
    uint256 amount;
    // Needed for dutch decaying inputs
    uint256 maxAmount;
    address recipient;
}

struct RebateOutput {
    // The ERC20 token address (or native ETH address)
    address token;
    uint256 decayStartTime;
    uint256 decayEndTime;
    // The amount of tokens at the start of the time period
    uint256 amount;
    // The amount of tokens at the end of the time period
    uint256 maxAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

struct ResolvedRelayOrder {
    OrderInfo info;
    bytes[] actions;
    InputTokenWithRecipient[] inputs;
    bytes sig;
    bytes32 hash;
}
