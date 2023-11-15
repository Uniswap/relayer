// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken} from "UniswapX/src/base/ReactorStructs.sol";

library OutputsBuilder {
    function single(address token, uint256 amount, address recipient) internal pure returns (OutputToken[] memory) {
        OutputToken[] memory result = new OutputToken[](1);
        result[0] = OutputToken(token, amount, recipient);
        return result;
    }

    /// TODO: Support multiple tokens + recipients
    function multiple(address token, uint256[] memory amounts, address recipient)
        internal
        pure
        returns (OutputToken[] memory)
    {
        OutputToken[] memory result = new OutputToken[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            result[i] = OutputToken(token, amounts[i], recipient);
        }
        return result;
    }
}
