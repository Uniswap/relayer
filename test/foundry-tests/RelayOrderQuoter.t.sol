// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayOrderQuoter} from "../../src/lens/RelayOrderQuoter.sol";
import {RelayOrder} from "../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../src/interfaces/IRelayOrderReactor.sol";
import {OrderInfo} from "../../src/base/ReactorStructs.sol";
import {Input, ResolvedRelayOrder} from "../../src/base/ReactorStructs.sol";
import {MockERC20} from "./util/mock/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {IRelayOrderReactor} from "../../src/interfaces/IRelayOrderReactor.sol";
import {PermitSignature} from "./util/PermitSignature.sol";
import {RelayOrderReactor} from "../../src/reactors/RelayOrderReactor.sol";
import {ReactorErrors} from "../../src/base/ReactorErrors.sol";

contract RelayOrderQuoterTest is Test, PermitSignature, DeployPermit2 {
    RelayOrderQuoter quoter;
    IRelayOrderReactor reactor;

    MockERC20 tokenIn;
    address swapper;
    IPermit2 permit2;
    uint256 swapperPrivateKey;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        quoter = new RelayOrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        permit2 = IPermit2(deployPermit2());
        // Use actions len = 0 to ensure we're not calling addr 0.
        reactor = new RelayOrderReactor(permit2, address(0));

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
        ResolvedRelayOrder memory quote = quoter.quote(abi.encode(order), sig);
        assertEq(address(quote.details[0].to), address(quoter));
        assertEq(quote.details[0].requestedAmount, ONE);
        assertEq(quote.permit.permitted[0].token, address(tokenIn));
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
        quoter.quote(abi.encode(order), sig);
    }
}
