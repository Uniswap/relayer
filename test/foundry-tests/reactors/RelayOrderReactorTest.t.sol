// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {OrderInfo, SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderLib, RelayInput, RelayOutput, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MockFillContractWithRebate} from "../util/mock/MockFillContractWithRebate.sol";

contract RelayOrderReactorTest is GasSnapshot, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    MockERC20 tokenIn;
    MockFillContractWithRebate fillContract;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;

    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        vm.chainId(1);

        tokenIn = new MockERC20("Input", "IN", 18);

        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());

        reactor = new RelayOrderReactor(permit2);

        fillContract = new MockFillContractWithRebate(address(reactor));

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
        tokenIn.mint(address(fillContract), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        RelayInput[] memory inputTokens = new RelayInput[](1);
        inputTokens[0] = RelayInput({
            token: tokenIn,
            startAmount: 0,
            endAmount: inputAmount,
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](1);
        actions[0] = hex"";

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            actions: actions,
            inputs: inputTokens,
            outputs: new RelayOutput[](0)
        });
        bytes32 orderHash = order.hash();

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        uint256 fillContractTokenInBefore = tokenIn.balanceOf(address(fillContract));

        // warp to precisely 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        snapStart("ExecuteSingle");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractTokenInBefore + 250000000000000000);
    }

    /// @dev Test of a simple execute with rebate required
    /// @dev this order has no actions and its inputs decay from 0 ether to 1 ether, and the outputs decay from 1 ether to 0
    function testExecuteSingleWithRebate() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(fillContract), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        RelayInput[] memory inputTokens = new RelayInput[](1);
        inputTokens[0] = RelayInput({
            token: tokenIn,
            startAmount: 0,
            endAmount: inputAmount,
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](1);
        actions[0] = "";

        RelayOutput[] memory outputTokens = new RelayOutput[](1);
        outputTokens[0] = RelayOutput({
            token: address(tokenIn),
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            startAmount: 1 ether,
            endAmount: 0,
            recipient: swapper
        });

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            inputs: inputTokens,
            outputs: outputTokens,
            actions: actions
        });

        bytes32 orderHash = order.hash();

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // warp to precisely 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(swapper), address(fillContract), 250000000000000000);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(fillContract), address(reactor), 750000000000000000);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(reactor), swapper, 750000000000000000);
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        snapStart("ExecuteSingleWithRebate");
        fillContract.execute(signedOrder);
        snapEnd();
    }
}
