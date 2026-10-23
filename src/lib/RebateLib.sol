// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Rebate} from "../base/ReactorStructs.sol";
import {ReactorErrors} from "../base/ReactorErrors.sol";

/// @notice Handles the EIP712 defined typehash and hashing for FeeEscalator, and performs escalation calculations
library RebateLib {
    using FixedPointMathLib for uint256;

    uint256 public constant BPS = 10000;

    bytes internal constant REBATE_TYPESTRING = abi.encodePacked(
        "Rebate(",
        "address token,",
        "uint256 minAmount,",
        "uint256 bpsPerGas)"
    );

    bytes32 internal constant REBATE_TYPEHASH = keccak256(REBATE_TYPESTRING);

    /// @notice
    function resolve(uint256 minAmount, uint256 bpsPerGas)
        internal
        view
        returns (uint256 resolvedAmount)
    {
        if(bpsPerGas == 0) {
            return minAmount;
        }
        uint256 priorityFee = tx.gasprice - block.basefee;
        return (minAmount * (BPS + (priorityFee * bpsPerGas))) / BPS;
    }

    function hash(Rebate memory rebate) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(REBATE_TYPEHASH, rebate.token, rebate.minAmount, rebate.bpsPerGas)
        );
    }
}
