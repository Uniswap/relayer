// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayOrder, RelayOrderLib} from "../../../src/lib/RelayOrderLib.sol";
import {OrderInfo, InputToken} from "UniswapX/src/base/ReactorStructs.sol";

contract PermitSignature is Test {
    using RelayOrderLib for RelayOrder;

    bytes32 public constant NAME_HASH = keccak256("Permit2");
    bytes32 public constant TYPE_HASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    string public constant _PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 constant RELAY_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(_PERMIT_BATCH_WITNESS_TRANSFER_TYPEHASH_STUB, RelayOrderLib.PERMIT2_ORDER_TYPE));

    function signOrder(uint256 privateKey, address permit2, RelayOrder memory order)
        internal
        view
        returns (bytes memory sig)
    {
        return getPermitSignature(
            privateKey, permit2, order.toPermit(), address(order.info.reactor), RELAY_ORDER_TYPE_HASH, order.hash()
        );
    }

    function getPermitSignature(
        uint256 privateKey,
        address permit2,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        address spender,
        bytes32 typeHash,
        bytes32 witness
    ) internal view returns (bytes memory sig) {
        uint256 numPermitted = permit.permitted.length;
        bytes32[] memory tokenPermissionHashes = new bytes32[](numPermitted);

        for (uint256 i = 0; i < numPermitted; ++i) {
            tokenPermissionHashes[i] = _hashTokenPermissions(permit.permitted[i]);
        }

        bytes32 msgHash = ECDSA.toTypedDataHash(
            _domainSeparatorV4(permit2),
            keccak256(
                abi.encode(
                    // TODO: fix for batch permit
                    typeHash,
                    keccak256(abi.encodePacked(tokenPermissionHashes)),
                    spender,
                    permit.nonce,
                    permit.deadline,
                    witness
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function _domainSeparatorV4(address permit2) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, NAME_HASH, block.chainid, permit2));
    }

    function _hashTokenPermissions(ISignatureTransfer.TokenPermissions memory permitted)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permitted));
    }
}
