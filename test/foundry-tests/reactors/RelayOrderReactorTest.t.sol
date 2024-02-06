// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Input, OrderInfo} from "../../../src/base/ReactorStructs.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {RelayOrderExecutor} from "../../../src/sample-executors/RelayOrderExecutor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {ONE} from "../util/Constants.sol";

contract RelayOrderReactorTest is GasSnapshot, Test, PermitSignature, DeployPermit2 {
    using RelayOrderLib for RelayOrder;
    using OrderInfoBuilder for OrderInfo;
    using InputBuilder for Input;
    using RelayOrderBuilder for RelayOrder;

    MockERC20 tokenIn;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;
    uint256 fillerPrivateKey;
    address filler;
    address constant MOCK_UNIVERSAL_ROUTER = address(0);

    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    error InvalidNonce();
    error SignatureExpired(uint256 deadline);

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);

        swapperPrivateKey = 0x12341234;
        fillerPrivateKey = 0xdead;
        swapper = vm.addr(swapperPrivateKey);
        filler = vm.addr(fillerPrivateKey);

        permit2 = IPermit2(deployPermit2());

        reactor = new RelayOrderReactor(permit2, MOCK_UNIVERSAL_ROUTER);

        // swapper approves permit2 to transfer tokens
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        assertEq(tokenIn.allowance(swapper, address(permit2)), type(uint256).max);
    }

    /// @dev Test of a simple execute
    /// @dev this order has no actions and its inputs decay from 0 ether to 1 ether
    function test_execute_withDecay() public {
        tokenIn.mint(address(swapper), ONE * 100);

        Input[] memory inputs = new Input[](1);
        inputs[0] = InputBuilder.init(tokenIn).withStartAmount(0); // Decay from 0 to 1.
        OrderInfo memory orderInfo =
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000);
        RelayOrder memory order = RelayOrderBuilder.init(orderInfo, inputs).withEndTime(block.timestamp + 1000);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // warp to 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(order.hash(), address(filler), swapper, order.info.nonce);
        // execute order
        vm.prank(filler);
        reactor.execute(signedOrder, filler);

        assertEq(tokenIn.balanceOf(address(filler)), 250000000000000000);
    }

    function test_multicall_execute_noDecay() public {
        tokenIn.mint(address(swapper), ONE * 100);
        // First order.
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order1.info = order1.info.withNonce(1); // Increment nonce.

        SignedOrder memory signedOrder0 =
            SignedOrder(abi.encode(order0), signOrder(swapperPrivateKey, address(permit2), order0));
        SignedOrder memory signedOrder1 =
            SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(permit2), order1));

        bytes[] memory actions = new bytes[](2);
        actions[0] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder0, filler);
        actions[1] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder1, filler);

        reactor.multicall(actions);

        assertEq(tokenIn.balanceOf(address(filler)), ONE * 2);
    }

    function test_multicall_execute_noDecay_multipleFeeRecipients() public {
        tokenIn.mint(address(swapper), ONE * 100);
        // First order.
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order1.info = order1.info.withNonce(1); // Increment nonce.

        SignedOrder memory signedOrder0 =
            SignedOrder(abi.encode(order0), signOrder(swapperPrivateKey, address(permit2), order0));
        SignedOrder memory signedOrder1 =
            SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(permit2), order1));

        bytes[] memory actions = new bytes[](2);
        actions[0] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder0, filler);
        actions[1] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder1, address(this));

        reactor.multicall(actions);

        assertEq(tokenIn.balanceOf(address(filler)), ONE);
        assertEq(tokenIn.balanceOf(address(this)), ONE);
    }

    function test_multicall_execute_noDecay_specifiedInputRecipients() public {
        tokenIn.mint(address(swapper), ONE * 100);
        // First order.
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order0.inputs[0] = order0.inputs[0].withRecipient(address(this));
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order1.inputs[0] = order1.inputs[0].withRecipient(address(this));
        order1.info = order1.info.withNonce(1); // Increment nonce.

        SignedOrder memory signedOrder0 =
            SignedOrder(abi.encode(order0), signOrder(swapperPrivateKey, address(permit2), order0));
        SignedOrder memory signedOrder1 =
            SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(permit2), order1));

        bytes[] memory actions = new bytes[](2);
        // Even if we specify a different feeRecipient, the inputs are received in this contract.
        actions[0] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder0, filler);
        actions[1] = abi.encodeWithSelector(IRelayOrderReactor.execute.selector, signedOrder1, filler);

        reactor.multicall(actions);

        assertEq(tokenIn.balanceOf(address(filler)), 0);
        assertEq(tokenIn.balanceOf(address(this)), ONE * 2);
    }

    function test_execute_reverts_InvalidReactor() public {
        address badReactor = address(0xbeef);
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, badReactor, swapper);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.prank(filler);
        vm.expectRevert(ReactorErrors.InvalidReactor.selector);
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_SignatureExpired() public {
        uint256 deadline = block.timestamp + 10;
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.info = order.info.withDeadline(deadline);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.warp(deadline + 1);
        vm.prank(filler);
        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_InvalidNonce() public {
        tokenIn.mint(address(swapper), ONE * 100);

        RelayOrder memory order =
            RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper).withEndTime(block.timestamp + 1000);
        order.info = order.info.withDeadline(block.timestamp + 1000);
        order.inputs[0] = order.inputs[0].withStartAmount(0); // Decay from 0 to 1.

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // warp to 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(order.hash(), address(filler), swapper, order.info.nonce);
        // expect we can execute the first order
        vm.prank(filler);
        reactor.execute(signedOrder, filler);
        assertEq(tokenIn.balanceOf(address(filler)), 250000000000000000);

        signedOrder = SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        // expect revert
        vm.prank(filler);
        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_EndTimeBeforeStartTime() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper).withStartTime(
            block.timestamp + 20
        ).withEndTime(block.timestamp + 10);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.prank(filler);
        vm.expectRevert(ReactorErrors.EndTimeBeforeStartTime.selector);
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_DeadlineBeforeEndTime() public {
        RelayOrder memory order =
            RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper).withEndTime(block.timestamp + 200);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.prank(filler);
        vm.expectRevert(ReactorErrors.DeadlineBeforeEndTime.selector);
        reactor.execute(signedOrder, filler);
    }
}
