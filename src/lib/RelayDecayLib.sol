// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling relay order objects
library RelayDecayLib {
    using FixedPointMathLib for uint256;

    /// @notice thrown if the decay direction is incorrect
    /// - for InputTokens, startAmount must be less than or equal to endAmount
    error InvalidAmounts();

    /// @notice calculates an amount using linear decay over time from decayStartTime to decayEndTime
    /// @dev handles both positive and negative decay depending on startAmount and endAmount
    /// @param startAmount The amount of tokens at decayStartTime
    /// @param endAmount The amount of tokens at decayEndTime
    /// @param decayStartTime The time to start decaying linearly
    /// @param decayEndTime The time to stop decaying linearly
    function decay(uint256 startAmount, uint256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (uint256 decayedAmount)
    {
        if (startAmount > endAmount) {
            revert InvalidAmounts();
        } else if (decayEndTime <= block.timestamp) {
            decayedAmount = endAmount;
        } else if (decayStartTime >= block.timestamp) {
            decayedAmount = startAmount;
        } else {
            unchecked {
                uint256 elapsed = block.timestamp - decayStartTime;
                uint256 duration = decayEndTime - decayStartTime;
                decayedAmount = startAmount + (endAmount - startAmount).mulDivDown(elapsed, duration);
            }
        }
    }
}
