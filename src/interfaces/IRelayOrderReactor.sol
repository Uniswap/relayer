// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IMulticall} from "./IMulticall.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Interface for the relay order reactors
interface IRelayOrderReactor is IMulticall {
    /// @notice Validates a user's relayed request, sends tokens to relevant addresses, and executes the relayed universalRouterCalldata.
    /// @param signedOrder Contains the raw relay order and signature bytes.
    /// @param feeRecipient The address to send the user's fee input.
    /// @dev Batch execute is enabled by using multicall.
    function execute(SignedOrder calldata signedOrder, address feeRecipient) external;

    /// @notice Shortcut for execute which sets the feeRecipient as msg.sender.
    function execute(SignedOrder calldata signedOrder) external;

    /// @notice Execute a signed 2612-style permit.
    /// @param token The token to permit.
    /// @param owner The signer of the permit.
    /// @param spender The approved spender.
    /// @param amount The amount allowed.
    /// @param deadline The expiration for the signature.
    /// @param v Must produce valid secp256k1 signature from the owner along with r and s.
    /// @param r Must produce valid secp256k1 signature from the owner along with v and s.
    /// @param s Must produce valid secp256k1 signature from the owner along with r and v.
    /// @dev Uses native 2612 permit if possible and falls back permit2 if not implemented on the token.
    /// @dev A permit request can be combined with an execute action through multicall.
    function permit(
        ERC20 token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
