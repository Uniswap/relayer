// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {DeployRelayOrderReactor} from "../../../script/DeployRelayOrderReactor.s.sol";
import {RelayOrder, OrderInfo, Input, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {RelayOrderLib} from "../../../src/lib/RelayOrderLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockUniversalRouter} from "../util/mock/MockUniversalRouter.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {FeeEscalatorBuilder} from "../util/FeeEscalatorBuilder.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract DeployRelayOrderReactorTest is Test, PermitSignature, DeployPermit2 {
    using RelayOrderLib for RelayOrder;
    using OrderInfoBuilder for OrderInfo;
    using InputBuilder for Input;
    using FeeEscalatorBuilder for FeeEscalator;
    using RelayOrderBuilder for RelayOrder;

    DeployRelayOrderReactor deployer;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 constant ONE = 10 ** 18;

    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);

    function setUp() public {
        deployPermit2();
        deployer = new DeployRelayOrderReactor();
        tokenIn = new MockERC20{salt: 0x00}("Token A", "TA", 18);
        tokenOut = new MockERC20{salt: 0x00}("Token B", "TB", 18);
    }

    function testDeploy() public {
        address mockUniversalRouter = address(new MockUniversalRouter());
        RelayOrderReactor reactor = deployer.run(mockUniversalRouter);

        assertEq(address(reactor.PERMIT2()), 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        assertEq(reactor.universalRouter(), mockUniversalRouter);
        quoteTest(reactor);
    }

    // e2e test the deployment
    function quoteTest(RelayOrderReactor reactor) public {
        uint256 swapperPrivateKey = 0x12341234;
        address swapper = vm.addr(swapperPrivateKey);
        address filler = makeAddr("filler");

        tokenIn.mint(address(swapper), 100 * ONE);
        tokenIn.forceApprove(swapper, address(reactor.PERMIT2()), 100 * ONE);

        RelayOrder memory order = RelayOrderBuilder.initDefault(tokenIn, address(reactor), swapper);
        order.input = order.input.withRecipient(address(this));
        order.universalRouterCalldata = abi.encodeWithSelector(MockUniversalRouter.success.selector);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(reactor.PERMIT2()), order));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(order.hash(), address(filler), swapper, order.info.nonce);
        // execute order
        vm.prank(filler);
        reactor.execute(signedOrder, filler);

        assertEq(tokenIn.balanceOf(address(this)), ONE);
        assertEq(tokenIn.balanceOf(filler), ONE);
    }
}
