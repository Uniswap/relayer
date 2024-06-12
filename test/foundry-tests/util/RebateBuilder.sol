// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Rebate} from "../../../src/base/ReactorStructs.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ONE} from "./Constants.sol";

library RebateBuilder {
    function init(ERC20 token) internal pure returns (Rebate memory) {
        // to not pay a rebate, submit a txn with 0 priority fee
        return Rebate({
            token: address(token),
            minAmount: 10000,
            bpsPerGas: 10
        });
    }

    function withMinAmount(Rebate memory rebate, uint256 _minAmount)
        internal
        pure
        returns (Rebate memory)
    {
        rebate.minAmount = _minAmount;
        return rebate;
    }

    function withBpsPerGas(Rebate memory rebate, uint256 _bpsPerGas) internal pure returns (Rebate memory) {
        rebate.bpsPerGas = _bpsPerGas;
        return rebate;
    }
}
