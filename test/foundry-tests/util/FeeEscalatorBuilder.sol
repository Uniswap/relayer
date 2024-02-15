// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ONE} from "./Constants.sol";

library FeeEscalatorBuilder {
    function init(ERC20 token) internal view returns (FeeEscalator memory) {
        // The default fee does not decay, so the start and end amounts are the same.
        return FeeEscalator({
            token: address(token),
            startAmount: ONE,
            endAmount: ONE,
            startTime: block.timestamp,
            endTime: block.timestamp
        });
    }

    function withStartAmount(FeeEscalator memory fee, uint256 _startAmount)
        internal
        pure
        returns (FeeEscalator memory)
    {
        fee.startAmount = _startAmount;
        return fee;
    }

    function withEndAmount(FeeEscalator memory fee, uint256 _endAmount) internal pure returns (FeeEscalator memory) {
        fee.endAmount = _endAmount;
        return fee;
    }

    function withStartTime(FeeEscalator memory fee, uint256 _startTime) internal pure returns (FeeEscalator memory) {
        fee.startTime = _startTime;
        return fee;
    }

    function withEndTime(FeeEscalator memory fee, uint256 _endTime) internal pure returns (FeeEscalator memory) {
        fee.endTime = _endTime;
        return fee;
    }
}
