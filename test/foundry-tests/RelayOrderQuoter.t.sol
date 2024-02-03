// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayOrderQuoter} from "../../src/lens/RelayOrderQuoter.sol";
import {RelayOrder} from "../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../src/interfaces/IRelayOrderReactor.sol";
import {OrderInfo} from "../../src/base/ReactorStructs.sol";
import {Input} from "../../src/base/ReactorStructs.sol";
import {MockERC20} from "./util/mock/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {IRelayOrderReactor} from "../../src/interfaces/IRelayOrderReactor.sol";
import {PermitSignature} from "./util/PermitSignature.sol";
import {RelayOrderReactor} from "../../src/reactors/RelayOrderReactor.sol";
import {ReactorErrors} from "../../src/base/ReactorErrors.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {MockUniversalRouter} from "./util/mock/MockUniversalRouter.sol";
import {SignatureVerification} from "permit2/src/libraries/SignatureVerification.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IMulticall} from "../../src/interfaces/IMulticall.sol";

contract RelayOrderQuoterTest is Test, PermitSignature, DeployPermit2 {
    RelayOrderQuoter quoter;
    IRelayOrderReactor reactor;

    MockERC20 tokenIn;
    address swapper;
    IPermit2 permit2;
    uint256 swapperPrivateKey;
    MockUniversalRouter universalRouter;

    uint256 constant ONE = 10 ** 18;

    error InvalidNonce();

    function setUp() public {
        quoter = new RelayOrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        permit2 = IPermit2(deployPermit2());
        universalRouter = new MockUniversalRouter();
        reactor = new RelayOrderReactor(permit2, address(universalRouter));

        swapperPrivateKey = 0x1234;
        swapper = vm.addr(swapperPrivateKey);
        tokenIn.mint(address(swapper), ONE);
    }

    function testGetReactor() public {
        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](1);

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({
                reactor: IRelayOrderReactor(address(0xbeef)),
                swapper: address(0),
                nonce: 0,
                deadline: block.timestamp + 100
            }),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });
        assertEq(address(quoter.getReactor(abi.encode(order))), address(0xbeef));
    }

    function testQuote() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        // Actions len = 0 to avoid the revert in UR.
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp + 100}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ISignatureTransfer.SignatureTransferDetails[] memory quote = quoter.quote(abi.encode(order), sig, address(this));
        assertEq(address(quote[0].to), address(this));
        assertEq(quote[0].requestedAmount, ONE);
    }

    function testQuoteMulticall() public {
        /// Sign usdc permit.
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                tokenIn.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        swapper,
                        address(permit2),
                        type(uint256).max - 1, // infinite approval
                        tokenIn.nonces(swapper),
                        type(uint256).max - 1 // infinite deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapperPrivateKey, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(signer, swapper);

        bytes memory permitData =
            abi.encode(swapper, address(permit2), type(uint256).max - 1, type(uint256).max - 1, v, r, s);

        Input[] memory inputs = new Input[](1);
        // Actions len = 0 to avoid the revert in UR.
        bytes[] memory actions = new bytes[](0);
        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp + 100}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        bytes[] memory multicallData = new bytes[](2);
        // Permit tokenIn
        multicallData[0] = abi.encodeWithSelector(IRelayOrderReactor.permit.selector, tokenIn, permitData);
        // Transfer tokenIn
        multicallData[1] = abi.encodeWithSelector(
            IRelayOrderReactor.execute.selector, SignedOrder(abi.encode(order), sig), address(this)
        );

        bytes[] memory quote = quoter.quoteMulticall(address(reactor), multicallData);
        bytes memory permitResult = quote[0];
        (ISignatureTransfer.SignatureTransferDetails[] memory transferResult) =
            abi.decode(quote[1], (ISignatureTransfer.SignatureTransferDetails[]));

        assertEq(permitResult.length, 0); // permit returns nothing

        assertEq(transferResult.length, 1);
        assertEq(address(transferResult[0].to), address(this));
        assertEq(transferResult[0].requestedAmount, ONE);
    }

    function testQuoteMulticallMinimal() public {
        /// Sign usdc permit.
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                tokenIn.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        swapper,
                        address(permit2),
                        type(uint256).max - 1, // infinite approval
                        tokenIn.nonces(swapper),
                        type(uint256).max - 1 // infinite deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapperPrivateKey, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(signer, swapper);

        bytes memory permitData =
            abi.encode(swapper, address(permit2), type(uint256).max - 1, type(uint256).max - 1, v, r, s);

        bytes[] memory multicallData = new bytes[](1);

        multicallData[0] = abi.encodeWithSelector(IRelayOrderReactor.permit.selector, tokenIn, permitData);

        bytes[] memory quote = quoter.quoteMulticall(address(reactor), multicallData);
        bytes memory permitResult = quote[0];

        assertEq(quote.length, 1); // Only permit result is returned
        assertEq(permitResult.length, 0); // Permit returns nothing
    }

    function testQuoteRevertsDeadlineBeforeEndTime() public {
        uint256 deadline = block.timestamp + 10;
        uint256 decayEndTime = deadline + 90;
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: decayEndTime,
            actions: actions,
            inputs: inputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(ReactorErrors.DeadlineBeforeEndTime.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testQuoteRevertsDeadlinePassed() public {
        uint256 deadline = block.timestamp;
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.warp(block.timestamp + 1);
        vm.expectRevert(ReactorErrors.DeadlinePassed.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testQuoteRevertsEndTimeBeforeStartTime() public {
        uint256 startTime = block.timestamp + 1;
        uint256 endTime = block.timestamp;
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: startTime,
            decayEndTime: endTime,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(ReactorErrors.EndTimeBeforeStartTime.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testQuoteMulticallRevertsEndTimeBeforeStartTime() public {
        /// Sign usdc permit.
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                tokenIn.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        swapper,
                        address(permit2),
                        type(uint256).max - 1, // infinite approval
                        tokenIn.nonces(swapper),
                        type(uint256).max - 1 // infinite deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapperPrivateKey, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(signer, swapper);

        bytes memory permitData =
            abi.encode(swapper, address(permit2), type(uint256).max - 1, type(uint256).max - 1, v, r, s);

        Input[] memory inputs = new Input[](1);
        // Actions len = 0 to avoid the revert in UR.
        bytes[] memory actions = new bytes[](0);
        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        uint256 startTime = block.timestamp + 1;
        uint256 endTime = block.timestamp;
        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: startTime,
            decayEndTime: endTime,
            actions: actions,
            inputs: inputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        bytes[] memory multicallData = new bytes[](2);
        // Permit tokenIn
        multicallData[0] = abi.encodeWithSelector(IRelayOrderReactor.permit.selector, tokenIn, permitData);
        // Transfer tokenIn
        multicallData[1] = abi.encodeWithSelector(
            IRelayOrderReactor.execute.selector, SignedOrder(abi.encode(order), sig), address(this)
        );

        vm.expectRevert(ReactorErrors.EndTimeBeforeStartTime.selector);
        quoter.quoteMulticall(address(reactor), multicallData);
    }

    function testQuoteRevertsTransferFailed() public {
        // no approval so transfer from permit2 will fail

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testQuoteRevertsUniversalRouterError() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](1);
        actions[0] = abi.encode(bytes4(keccak256("FakeSelector()"))); // Will just execute the fallback call and revert.

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(MockUniversalRouter.UniversalRouterError.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testRevertInvalidNonce() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        vm.prank(swapper);
        permit2.invalidateUnorderedNonces(0, 1); // Invalidates the first nonce.

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(InvalidNonce.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }

    function testRevertInvalidSigner() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        Input[] memory inputs = new Input[](1);
        bytes[] memory actions = new bytes[](0);

        inputs[0] = Input({token: address(tokenIn), recipient: address(0), startAmount: ONE, maxAmount: ONE});

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: reactor, swapper: swapper, nonce: 0, deadline: block.timestamp}),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp,
            actions: actions,
            inputs: inputs
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        order.info.swapper = address(0xbeef); // Incorrect swapper;
        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        quoter.quote(abi.encode(order), sig, address(this));
    }
}
