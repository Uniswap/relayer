// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";

/// @notice Sample executor for Relay orders
/// @dev this contract acts like a fee collector for relay orders
contract RelayOrderExecutor is Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if this contract is called by an address other than the whitelisted caller
    error CallerNotWhitelisted();

    event WhitelistedCallerChanged(address indexed newWhitelistedCaller);

    address private whitelistedCaller;
    IRelayOrderReactor private immutable reactor;

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    constructor(address _whitelistedCaller, IRelayOrderReactor _reactor, address _owner) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
    }

    /// @notice Shortcut to execute a single relay order
    /// @param order The order to execute
    function execute(SignedOrder calldata order) external onlyWhitelistedCaller {
        reactor.execute(order);
    }

    /// @notice Call multiple functions on the reactor
    /// @param data encoded function data for each of the calls
    /// @return results return values from each of the calls
    /// @dev use for execute batch and 2612 permits
    function multicall(bytes[] calldata data) external onlyWhitelistedCaller returns (bytes[] memory results) {
        return reactor.multicall(data);
    }

    /// @notice Transfer all tokens in this contract to the recipient. Can only be called by owner.
    /// @param tokens The tokens to withdraw
    /// @param recipient The recipient of the tokens
    function withdrawERC20(ERC20[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = tokens[i];
            token.safeTransfer(recipient, token.balanceOf(address(this)));
        }
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Change the whitelisted caller
    /// @param newWhitelistedCaller The new whitelisted caller
    function changeWhitelistedCaller(address newWhitelistedCaller) external onlyOwner {
        whitelistedCaller = newWhitelistedCaller;
        emit WhitelistedCallerChanged(newWhitelistedCaller);
    }

    receive() external payable {}
}
