// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice A mock universal router that will always revert.
contract MockUniversalRouter {
    error UniversalRouterError();

    function succeeds() public pure {}

    function succeedsWithReturn() public pure returns (bool) {
        return true;
    }

    fallback() external {
        revert UniversalRouterError();
    }
}
