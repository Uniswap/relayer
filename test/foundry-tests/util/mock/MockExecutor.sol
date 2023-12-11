// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {IReactorCallback} from "UniswapX/src/interfaces/IReactorCallback.sol";
import {OutputToken, SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ResolvedRelayOrder, InputTokenWithRecipient} from "../../../../src/base/ReactorStructs.sol";

contract MockFillContract {
    using CurrencyLibrary for address;

    IReactor immutable reactor;

    constructor(address _reactor) {
        reactor = IReactor(_reactor);
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order) external {
        reactor.executeWithCallback(order, hex"");
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(SignedOrder[] calldata orders) external {
        reactor.executeBatchWithCallback(orders, hex"");
    }

    function reactorCallback(ResolvedRelayOrder[] memory resolvedOrders, bytes memory) external {
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            for (uint256 j = 0; j < resolvedOrders[i].inputs.length; j++) {
                InputTokenWithRecipient memory input = resolvedOrders[i].inputs[j];
                // only need to transfer to reactor if negative (swapper is owed)
                if (input.amount < 0) {
                    if (address(input.token).isNative()) {
                        CurrencyLibrary.transferNative(address(reactor), uint256(-input.amount));
                    } else {
                        input.token.transfer(address(reactor), uint256(-input.amount));
                    }
                }
            }
        }
    }
}
