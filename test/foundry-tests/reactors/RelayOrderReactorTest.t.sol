// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Input, OrderInfo, ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {RelayOrderExecutor} from "../../../src/sample-executors/RelayOrderExecutor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract RelayOrderReactorTest is GasSnapshot, Test, PermitSignature, DeployPermit2 {
    using RelayOrderLib for RelayOrder;

    MockERC20 tokenIn;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;
    uint256 fillerPrivateKey;
    address filler;

    RelayOrderExecutor executor;

    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    error InvalidNonce();

    function setUp() public {
        vm.chainId(1);

        tokenIn = new MockERC20("Input", "IN", 18);

        swapperPrivateKey = 0x12341234;
        fillerPrivateKey = 0xdead;
        swapper = vm.addr(swapperPrivateKey);
        filler = vm.addr(fillerPrivateKey);

        permit2 = IPermit2(deployPermit2());

        reactor = new RelayOrderReactor(permit2);
        // filler is also owner of executor
        executor = new RelayOrderExecutor(filler, IRelayOrderReactor(reactor), filler);

        // swapper approves permit2 to transfer tokens
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        assertEq(tokenIn.allowance(swapper, address(permit2)), type(uint256).max);
    }

    /// @dev Test of a simple execute
    /// @dev this order has no actions and its inputs decay from 0 ether to 1 ether
    function testExecuteSingle() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(executor), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        Input[] memory inputs = new Input[](1);
        inputs[0] = Input({
            token: address(tokenIn),
            startAmount: 0,
            maxAmount: inputAmount,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](0);

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: IRelayOrderReactor(reactor), swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            actions: actions,
            inputs: inputs
        });
        bytes32 orderHash = order.hash();

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        uint256 executorTokenInBefore = tokenIn.balanceOf(address(executor));

        // warp to 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(executor), swapper, order.info.nonce);
        // execute order
        vm.prank(filler);
        snapStart("ExecuteSingle");
        executor.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(executor)), executorTokenInBefore + 250000000000000000);
    }

    function testExecuteInvalidReactor() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        address otherReactor = vm.addr(0xdead);

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(executor), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        Input[] memory inputs = new Input[](1);
        inputs[0] = Input({
            token: address(tokenIn),
            startAmount: 0,
            maxAmount: inputAmount,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](0);

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: IRelayOrderReactor(otherReactor), swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.prank(filler);
        vm.expectRevert(ReactorErrors.InvalidReactor.selector);
        executor.execute(signedOrder);
    }

    function testExecuteDeadlinePassed() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp - 1;
        address otherReactor = vm.addr(0xdead);

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(executor), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        Input[] memory inputs = new Input[](1);
        inputs[0] = Input({
            token: address(tokenIn),
            startAmount: 0,
            maxAmount: inputAmount,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](0);

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: IRelayOrderReactor(otherReactor), swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.prank(filler);
        vm.expectRevert(ReactorErrors.DeadlinePassed.selector);
        executor.execute(signedOrder);
    }

    function testExecuteNonceReuse() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(executor), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        Input[] memory inputs = new Input[](1);
        inputs[0] = Input({
            token: address(tokenIn),
            startAmount: 0,
            maxAmount: inputAmount,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](0);

        RelayOrder memory order = RelayOrder({
            info: OrderInfo({reactor: IRelayOrderReactor(reactor), swapper: swapper, nonce: 0, deadline: deadline}),
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            actions: actions,
            inputs: inputs
        });
        bytes32 orderHash = order.hash();

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        uint256 executorTokenInBefore = tokenIn.balanceOf(address(executor));

        // warp to 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(executor), swapper, order.info.nonce);
        // expect we can execute the first order
        vm.prank(filler);
        executor.execute(signedOrder);
        assertEq(tokenIn.balanceOf(address(executor)), executorTokenInBefore + 250000000000000000);

        // change deadline to sig and orderHash are different
        order.info.deadline = block.timestamp + 1500;
        // however nonce 0 will have been used
        signedOrder = SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        // expect revert
        vm.prank(filler);
        vm.expectRevert(InvalidNonce.selector);
        executor.execute(signedOrder);
    }
}
