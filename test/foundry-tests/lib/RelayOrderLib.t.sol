// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayOrderLib} from "../../../src/lib/RelayOrderLib.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {MockReactor} from "../util/mock/MockReactor.sol";
import {RelayOrder, OrderInfo, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {ReactorErrors} from "../../../src/base/ReactorErrors.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {FeeEscalatorBuilder} from "../util/FeeEscalatorBuilder.sol";

contract RelayOrderLibTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using FeeEscalatorBuilder for FeeEscalator;

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
}
