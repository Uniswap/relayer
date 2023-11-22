// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

address constant NATIVE = 0x0000000000000000000000000000000000000000;
uint256 constant TRANSFER_NATIVE_GAS_LIMIT = 6900;

/// @title CurrencyLibrary
/// @dev This library allows for transferring native ETH and ERC20s via direct filler OR fill contract.
library CurrencyLibrary {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when a native transfer fails
    error NativeTransferFailed();
    /// @notice Thrown for insufficient balance
    error InsufficientBalance();

    /// @notice Get the balance of a currency for addr
    /// @param currency The currency to get the balance of
    /// @param addr The address to get the balance of
    /// @return balance The balance of the currency for addr
    function balanceOf(address currency, address addr) internal view returns (uint256 balance) {
        if (isNative(currency)) {
            balance = addr.balance;
        } else {
            balance = ERC20(currency).balanceOf(addr);
        }
    }

    /// @notice Transfer this contract's entire balance of a currency to recipient
    /// @param currency The currency to transfer
    /// @param recipient The recipient of the currency
    /// @param minAmount The minAmount of currency that must be transferred
    function transferFillFromBalance(address currency, address recipient, uint256 minAmount) internal {
        if (isNative(currency)) {
            if (address(this).balance < minAmount) revert InsufficientBalance();
            // we will have received native assets directly so can directly transfer
            transferNative(recipient, address(this).balance);
        } else {
            uint256 balance = ERC20(currency).balanceOf(address(this));
            if (balance < minAmount) revert InsufficientBalance();
            ERC20(currency).transfer(recipient, balance);
        }
    }

    /// @notice Transfer native currency to recipient
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    function transferNative(address recipient, uint256 amount) internal {
        (bool success,) = recipient.call{value: amount, gas: TRANSFER_NATIVE_GAS_LIMIT}("");
        if (!success) revert NativeTransferFailed();
    }

    /// @notice returns true if currency is native
    /// @param currency The currency to check
    /// @return true if currency is native
    function isNative(address currency) internal pure returns (bool) {
        return currency == NATIVE;
    }
}
