// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";
import {IRelayOrderReactor} from "../interfaces/IRelayOrderReactor.sol";

/// @notice 
contract RelayOrderExecutor is Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if this contract is called by an address other than the whitelisted caller
    error CallerNotWhitelisted();

    address private immutable whitelistedCaller;
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

    /// @notice the reactor performs no verification that the user's signed permit is executed correctly
    ///         e.g. if the necessary approvals are already set, a filler can call this function or the standard execute function to fill the order
    /// @dev assume 2612 permit is collected offchain
    function executeWithPermit(SignedOrder calldata order, bytes calldata permitData)
        external
        onlyWhitelistedCaller
    {
        _permit(permitData);
        execute(order);
    }

    /// @notice assume that we already have all output tokens
    /// @dev assume 2612 permits are collected offchain
    function executeBatchWithPermit(SignedOrder[] calldata orders, bytes[] calldata permitData)
        external
        payable
        onlyWhitelistedCaller
    {
        _permitBatch(permitData);
        executeBatch(orders);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    /// must be called before the call to the reactor
    function _permit(bytes calldata permitData) internal {
        (address token, bytes memory data) = abi.decode(permitData, (address, bytes));
        (address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        Permit2Lib.permit2(ERC20(token), _owner, spender, value, deadline, v, r, s);
    }

    function _permitBatch(bytes[] calldata permitData) internal {
        for (uint256 i = 0; i < permitData.length; i++) {
            _permit(permitData[i]);
        }
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

    receive() external payable {}
}
