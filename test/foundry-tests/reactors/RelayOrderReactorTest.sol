// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {OrderInfo, SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {InputTokenWithRecipient, ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MockFillContract} from "../util/mock/MockExecutor.sol";

contract RelayOrderReactorTest is GasSnapshot, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;

    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed swapper, uint256 nonce);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());
        reactor = new RelayOrderReactor(permit2);

        fillContract = new MockFillContract(address(reactor));
    }

    /// @notice Create and return a basic single Relay order along with its signature, orderHash, and orderInfo
    function createAndSignOrder(ResolvedRelayOrder memory resolvedOrder)
        public
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        RelayOrder memory order = RelayOrder({
            info: resolvedOrder.info,
            decayStartTime: block.timestamp,
            decayEndTime: resolvedOrder.info.deadline,
            actions: resolvedOrder.actions,
            inputs: resolvedOrder.inputs
        });
        orderHash = order.hash();
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    /// @dev Test of a simple execute
    function testBaseExecute() public {
        uint256 inputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenIn.mint(address(fillContract), uint256(inputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](1);
        inputTokens[0] = InputTokenWithRecipient({
            token: tokenIn,
            amount: -int256(inputAmount),
            maxAmount: int256(inputAmount),
            // sending to filler
            recipient: address(0)
        });

        bytes[] memory actions = new bytes[](1);
        actions[0] = "";

        ResolvedRelayOrder memory order = ResolvedRelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            inputs: inputTokens,
            actions: actions,
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        // warp to precisely 25% way through the decay
        vm.warp(block.timestamp + 250);

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(fillContract), address(reactor), 500000000000000000);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(reactor), swapper, 500000000000000000);
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        snapStart("ExecuteSingle");
        fillContract.execute(signedOrder);
        snapEnd();
    }
}
