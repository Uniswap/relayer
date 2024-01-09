// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ReactorErrors {
    /// @notice thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice thrown when an order's end time is before its start time
    error OrderEndTimeBeforeStartTime();

    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();

    /// @notice thrown if the order has expired
    error DeadlinePassed();

    /// @notice thrown if the array lengths are mismatched for various inputs
    error LengthMismatch();
}
