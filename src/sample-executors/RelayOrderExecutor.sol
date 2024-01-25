// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";
import {Multicall} from "./Multicall.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";

/// @notice Sample executor for Relay orders
contract RelayOrderExecutor is Multicall, Owned {
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

    /// @notice Execute a single relay order
    function execute(SignedOrder calldata order) public onlyWhitelistedCaller {
        reactor.execute(order);
    }

    /// @notice Execute a batch of relay orders
    function executeBatch(SignedOrder[] calldata orders) public onlyWhitelistedCaller {
        reactor.executeBatch(orders);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    /// must be called before the call to the reactor
    function permit(bytes calldata permitData) public {
        (address token, bytes memory data) = abi.decode(permitData, (address, bytes));
        (address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        Permit2Lib.permit2(ERC20(token), _owner, spender, value, deadline, v, r, s);
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
