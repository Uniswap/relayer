// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IReactor} from "UniswapX/src/interfaces/IReactor.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {ResolvedRelayOrder, RebateOutput, OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactorCallback} from "../../../../src/interfaces/IRelayOrderReactorCallback.sol";

contract MockFillContractWithRebate is IRelayOrderReactorCallback {
    using CurrencyLibrary for address;

    IReactor immutable reactor;

    constructor(address _reactor) {
        reactor = IReactor(_reactor);
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order) external payable {
        reactor.execute{value: msg.value}(order);
    }

    /// @notice assume that we already have all output tokens
    function reactorCallback(ResolvedRelayOrder memory, bytes memory callbackData) external payable {
        (RebateOutput memory output) = abi.decode(callbackData, (RebateOutput));
        if (output.token.isNative()) {
            CurrencyLibrary.transferNative(address(reactor), output.amount);
        } else {
            ERC20(output.token).transfer(address(reactor), output.amount);
        }
    }
}
