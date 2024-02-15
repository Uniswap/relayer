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

contract RelayOrderLibTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using FeeEscalatorBuilder for FeeEscalator;
    using InputBuilder for Input;

    address swapper;
    MockReactor reactor;
    MockERC20 token;

    function setUp() public {
        swapper = makeAddr("swapper");
        reactor = new MockReactor();
        token = new MockERC20("Token", "TK", 18);
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

    function test_fuzz_toTransferDetails_noEscalation(uint256 startAmount, uint256 endAmount) public {
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
        assertEq(details[1].requestedAmount, order.fee.startAmount);
    }

    function test_toTransferDetails_noEscalation_try() public {
        uint256 startAmount = 0;
        uint256 endAmount = 1;
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
        assertEq(details[1].requestedAmount, order.fee.startAmount);
    }
}
