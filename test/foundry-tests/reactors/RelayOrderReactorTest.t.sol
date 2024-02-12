// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Input, OrderInfo, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {FeeEscalatorBuilder} from "../util/FeeEscalatorBuilder.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {ONE} from "../util/Constants.sol";

contract RelayOrderReactorTest is GasSnapshot, Test, PermitSignature, DeployPermit2 {
    using RelayOrderLib for RelayOrder;
    using OrderInfoBuilder for OrderInfo;
    using InputBuilder for Input;
    using FeeEscalatorBuilder for FeeEscalator;
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
    /// @dev this order has no actions and its fee increases from 0 ether to 1 ether
    function test_execute_withDecay() public {
        tokenIn.mint(address(swapper), ONE * 100);

        Input[] memory inputs = new Input[](1);
        inputs[0] = InputBuilder.init(tokenIn).withAmount(ONE);

        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(tokenIn).withStartAmount(0).withMaxAmount(ONE).withEndTime(block.timestamp + 1000);
        OrderInfo memory orderInfo =
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000);
        RelayOrder memory order = RelayOrderBuilder.init(orderInfo, inputs, fee);

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

    function test_execute_noInputsOrFee() public {
        Input[] memory inputs = new Input[](0);
        FeeEscalator memory noFee;

        OrderInfo memory orderInfo =
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000);
        RelayOrder memory order = RelayOrderBuilder.init(orderInfo, inputs, noFee);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(order.hash(), address(filler), swapper, order.info.nonce);
        // should be fillable
        vm.prank(filler);
        reactor.execute(signedOrder, filler);
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
        FeeEscalator memory noFee;

        tokenIn.mint(address(swapper), ONE * 100);
        // First order.
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper).withFee(noFee);
        order0.inputs[0] = order0.inputs[0].withRecipient(address(this));
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper).withFee(noFee);
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
        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_NoInputsSignatureExpired() public {
        uint256 deadline = block.timestamp + 10;
        Input[] memory inputs = new Input[](0);
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.inputs = inputs;
        order.info = order.info.withDeadline(deadline);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(SignatureExpired.selector, deadline));
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_InvalidNonce() public {
        tokenIn.mint(address(swapper), ONE * 100);

        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.info = order.info.withDeadline(block.timestamp + 1000);
        order.fee = order.fee.withStartAmount(0).withMaxAmount(ONE).withEndTime(block.timestamp + 1000); // increase from 0 to 1.

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
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.fee = order.fee.withEndTime(block.timestamp + 100);
        order.fee = order.fee.withStartTime(block.timestamp + 200);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.expectRevert(ReactorErrors.EndTimeBeforeStartTime.selector);
        reactor.execute(signedOrder, filler);
    }

    function test_execute_reverts_DeadlineBeforeEndTime() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.info = order.info.withDeadline(block.timestamp + 100);
        order.fee = order.fee.withEndTime(block.timestamp + 200);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        vm.expectRevert(ReactorErrors.DeadlineBeforeEndTime.selector);
        reactor.execute(signedOrder, filler);
    }
}
