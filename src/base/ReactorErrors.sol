// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ReactorErrors {
    // Occurs when an output = ETH and the reactor does contain enough ETH but
    // the direct filler did not include enough ETH in their call to execute/executeBatch
    error InsufficientEth();

    // A nested call failed
    error CallFailed();

    /// @notice thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice thrown when an order's end time is before its start time
    error OrderEndTimeBeforeStartTime();

    /// @notice thrown when an order's inputs and outputs both decay
    error InputAndOutputDecay();
}
