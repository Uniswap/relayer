// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {RelayOrderInfo} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";

library RelayOrderInfoBuilder {
    function init(address reactor) internal view returns (RelayOrderInfo memory) {
        return RelayOrderInfo({reactor: reactor, swapper: address(0), nonce: 0, deadline: block.timestamp + 100});
    }

    function withSwapper(RelayOrderInfo memory info, address _swapper) internal pure returns (RelayOrderInfo memory) {
        info.swapper = _swapper;
        return info;
    }

    function withNonce(RelayOrderInfo memory info, uint256 _nonce) internal pure returns (RelayOrderInfo memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(RelayOrderInfo memory info, uint256 _deadline)
        internal
        pure
        returns (RelayOrderInfo memory)
    {
        info.deadline = _deadline;
        return info;
    }
}
