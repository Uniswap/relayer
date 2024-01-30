// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice Handles all calls to the universal router.
library ActionsLib {
    function execute(bytes[] memory actions, address universalRouter) internal {
        uint256 actionsLength = actions.length;
        for (uint256 i = 0; i < actionsLength;) {
            (bool success, bytes memory result) = universalRouter.call(actions[i]);
            if (!success) {
                // bubble up all errors, including custom errors which are encoded like functions
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            unchecked {
                i++;
            }
        }
    }
}
