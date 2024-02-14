// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ReactorErrors {
    /// @notice Thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice Thrown when an order's end time is before its start time
    error EndTimeBeforeStartTime();

    /// @notice Thrown if the escalation direction is incorrect
    error InvalidAmounts();

    /// @notice Thrown when the order targets a different reactor
    error InvalidReactor();

    /// @notice Thrown if the order has expired
    error DeadlinePassed();
}
