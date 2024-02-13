// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {RelayOrderLib} from "../../../src/lib/RelayOrderLib.sol";
import {OrderInfo} from "UniswapX/src/base/ReactorStructs.sol";
import {Input, RelayOrder} from "../../../src/base/ReactorStructs.sol";

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
        ISignatureTransfer.TokenPermissions[] memory permissions = order.toTokenPermissions();

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permissions,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
        return getPermitSignature(
            privateKey, permit2, permit, address(order.info.reactor), RELAY_ORDER_TYPE_HASH, order.hash()
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

    /// @notice Generate permit data for a token to be submitted to permit on the reactor
    function generatePermitData(address permit2, ERC20 token, uint256 signerPrivateKey) internal returns (bytes memory permitData) {
        address signer = vm.addr(signerPrivateKey);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        signer,
                        permit2,
                        type(uint256).max - 1, // infinite approval
                        token.nonces(signer),
                        type(uint256).max - 1 // infinite deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        assertEq(ecrecover(digest, v, r, s), signer);

        permitData = abi.encode(signer, permit2, type(uint256).max - 1, type(uint256).max - 1, v, r, s);
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
