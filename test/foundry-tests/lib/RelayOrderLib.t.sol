// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayOrderLib} from "../../../src/lib/RelayOrderLib.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {MockReactor} from "../util/mock/MockReactor.sol";
import {RelayOrder, OrderInfo, FeeEscalator, Input} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {FeeEscalatorBuilder} from "../util/FeeEscalatorBuilder.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";

contract RelayOrderLibTest is Test, DeployPermit2, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using FeeEscalatorBuilder for FeeEscalator;
    using InputBuilder for Input;

    address swapper;
    uint256 swapperPrivateKey;
    MockReactor reactor;
    MockERC20 token;
    IPermit2 permit2;
    uint256 ONE = 10 ** 18;

    function setUp() public {
        swapperPrivateKey = 0x1234;
        swapper = vm.addr(swapperPrivateKey);
        reactor = new MockReactor();
        token = new MockERC20("Token", "TK", 18);
        permit2 = IPermit2(deployPermit2());

        token.forceApprove(swapper, address(permit2), type(uint256).max);
        assertEq(token.allowance(swapper, address(permit2)), type(uint256).max);
        token.mint(swapper, ONE * 2);
    }

    function test_validate_succeeds() public view {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        reactor.validate(order); // Use mock reactor to pass validation since address(this) must be reactor.
    }

    function test_validate_reverts_DeadlineBeforeEndTime() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.info = order.info.withDeadline(block.timestamp + 1);
        order.fee = order.fee.withEndTime(block.timestamp + 2);

        vm.expectRevert(ReactorErrors.DeadlineBeforeEndTime.selector);
        RelayOrderLib.validate(order);
    }

    function test_validate_reverts_InvalidReactor() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.info.reactor = IRelayOrderReactor(address(0));
        vm.expectRevert(ReactorErrors.InvalidReactor.selector);
        reactor.validate(order);
    }

    function test_toTokenPermissions_default() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        ISignatureTransfer.TokenPermissions[] memory permissions = RelayOrderLib.toTokenPermissions(order);
        assertEq(permissions.length, 2);
        assertEq(permissions[0].token, address(token));
        assertEq(permissions[1].token, address(token));
        assertEq(permissions[0].amount, order.input.amount);
        assertEq(permissions[1].amount, order.fee.endAmount);
    }

    function test_fuzz_toTokenPermissions(uint256 inputAmount, uint256 startAmount, uint256 endAmount) public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.input = order.input.withAmount(inputAmount);
        order.fee = order.fee.withStartAmount(startAmount).withEndAmount(endAmount);
        ISignatureTransfer.TokenPermissions[] memory permissions = RelayOrderLib.toTokenPermissions(order);
        assertEq(permissions.length, 2);
        assertEq(permissions[0].token, address(token));
        assertEq(permissions[1].token, address(token));
        assertEq(permissions[0].amount, order.input.amount);
        assertEq(permissions[1].amount, order.fee.endAmount);
    }

    function test_toTransferDetails_noEscalation() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            RelayOrderLib.toTransferDetails(order, address(this));
        assertEq(details.length, 2);
        assertEq(details[0].to, address(0));
        assertEq(details[0].requestedAmount, order.input.amount);
        assertEq(details[1].to, address(this));
        assertEq(details[1].requestedAmount, order.fee.startAmount);
    }

    function test_fuzz_toTransferDetails_noEscalation_atBlockTimestamp(uint256 startAmount, uint256 endAmount) public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.fee = order.fee.withStartAmount(startAmount).withEndAmount(endAmount);
        if (startAmount > endAmount) {
            vm.expectRevert(ReactorErrors.InvalidAmounts.selector);
        }
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            RelayOrderLib.toTransferDetails(order, address(this));
        assertEq(details.length, 2);
        assertEq(details[0].to, address(0));
        assertEq(details[0].requestedAmount, order.input.amount);
        assertEq(details[1].to, address(this));
        assertEq(details[1].requestedAmount, order.fee.endAmount);
    }

    function test_fuzz_toTransferDetails_noEscalation_beforeBlockTimestamp(uint256 startAmount, uint256 endAmount)
        public
    {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.fee = order.fee.withStartAmount(startAmount).withEndAmount(endAmount).withStartTime(block.timestamp + 1)
            .withEndTime(block.timestamp + 1);
        if (startAmount > endAmount) {
            vm.expectRevert(ReactorErrors.InvalidAmounts.selector);
        }
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            RelayOrderLib.toTransferDetails(order, address(this));
        assertEq(details.length, 2);
        assertEq(details[0].to, address(0));
        assertEq(details[0].requestedAmount, order.input.amount);
        assertEq(details[1].to, address(this));
        assertEq(details[1].requestedAmount, order.fee.startAmount);
    }

    function test_fuzz_toTransferDetails_noEscalation_afterBlockTimestamp(uint256 startAmount, uint256 endAmount)
        public
    {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.fee = order.fee.withStartAmount(startAmount).withEndAmount(endAmount).withStartTime(block.timestamp + 1)
            .withEndTime(block.timestamp + 1);
        if (startAmount > endAmount) {
            vm.expectRevert(ReactorErrors.InvalidAmounts.selector);
        }
        vm.warp(block.timestamp + 1);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            RelayOrderLib.toTransferDetails(order, address(this));
        assertEq(details.length, 2);
        assertEq(details[0].to, address(0));
        assertEq(details[0].requestedAmount, order.input.amount);
        assertEq(details[1].to, address(this));
        assertEq(details[1].requestedAmount, order.fee.endAmount);
    }

    function test_toTransferDetails_midPointEscalation() public {
        uint256 startAmount = 20 ether;
        uint256 endAmount = 30 ether;

        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.fee = order.fee.withStartTime(100).withEndTime(200).withStartAmount(startAmount).withEndAmount(endAmount);
        vm.warp(150);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            RelayOrderLib.toTransferDetails(order, address(this));

        assertEq(details.length, 2);
        assertEq(details[0].to, address(0));
        assertEq(details[0].requestedAmount, order.input.amount);
        assertEq(details[1].to, address(this));
        assertEq(details[1].requestedAmount, 25 ether);
    }

    function test_transferInputTokens_noEscalation_toAddressThis() public {
        RelayOrder memory order = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order.input = order.input.withRecipient(address(this));
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        reactor.transferInputTokens(order, RelayOrderLib.hash(order), permit2, address(this), signedOrder.sig);

        assertEq(token.balanceOf(address(this)), ONE * 2);
    }

    // Note: This doesn't check for 712 correctness, just accounts for accidental changes to the lib file
    function test_Permit2WitnessStubTypestring_isCorrect() public {
        bytes memory typestring =
            "RelayOrder witness)FeeEscalator(address token,uint256 startAmount,uint256 endAmount,uint256 startTime,uint256 endTime)Input(address token,uint256 amount,address recipient)OrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline)RelayOrder(OrderInfo info,Input input,FeeEscalator fee,bytes universalRouterCalldata)TokenPermissions(address token,uint256 amount)";
        assertEq(string(typestring), RelayOrderLib.PERMIT2_ORDER_TYPE);
    }

    // Note: This doesn't check for 712 correctness, just accounts for accidental changes to the lib file
    function test_RelayOrderTypestring_isCorrect() public {
        bytes memory typestring =
            "RelayOrder(OrderInfo info,Input input,FeeEscalator fee,bytes universalRouterCalldata)FeeEscalator(address token,uint256 startAmount,uint256 endAmount,uint256 startTime,uint256 endTime)Input(address token,uint256 amount,address recipient)OrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline)";
        assertEq(typestring, RelayOrderLib.FULL_RELAY_ORDER_TYPESTRING);
        assertEq(keccak256(typestring), RelayOrderLib.FULL_RELAY_ORDER_TYPEHASH);
    }

    function test_hash_isEqual() public {
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        assertEq(RelayOrderLib.hash(order0), RelayOrderLib.hash(order1));
    }

    function test_hash_isDifferentByOrderInfo() public {
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order0.info = order0.info.withSwapper(address(0xfeed));
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order1.info = order1.info.withSwapper(address(0xbeef));
        assertTrue(RelayOrderLib.hash(order0) != RelayOrderLib.hash(order1));
    }

    function test_hash_isDifferentByInput() public {
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order0.input = order0.input.withToken(address(0x123));
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order1.input = order1.input.withToken(address(0x321));
        assertTrue(RelayOrderLib.hash(order0) != RelayOrderLib.hash(order1));
    }

    function test_hash_isDifferentByFeeEscalator() public {
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order0.fee = order0.fee.withEndAmount(ONE * 10);
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order1.fee = order1.fee.withEndAmount(ONE * 100);
        assertTrue(RelayOrderLib.hash(order0) != RelayOrderLib.hash(order1));
    }

    function test_hash_isDifferentByCalldata() public {
        RelayOrder memory order0 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order0.universalRouterCalldata = bytes("123");
        RelayOrder memory order1 = RelayOrderBuilder.initDefault(token, address(reactor), swapper);
        order1.universalRouterCalldata = bytes("0123");
        assertTrue(RelayOrderLib.hash(order0) != RelayOrderLib.hash(order1));
    }
}
