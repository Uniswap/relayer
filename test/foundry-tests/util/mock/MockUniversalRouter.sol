// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice A mock universal router that will always revert.
contract MockUniversalRouter {
    error UniversalRouterError();

    fallback() external {
        revert UniversalRouterError();
    }
}
