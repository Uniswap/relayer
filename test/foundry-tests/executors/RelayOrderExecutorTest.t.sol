// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test} from "forge-std/Test.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "UniswapX/test/util/DeployPermit2.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {Input, OrderInfo, ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {RelayOrderExecutor} from "../../../src/sample-executors/RelayOrderExecutor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract RelayOrderExecutorTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    MockERC20 tokenIn;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;
    uint256 callerPrivateKey;
    address whitelistedCaller;
    uint256 ownerPrivateKey;
    address owner;

    RelayOrderExecutor executor;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        vm.chainId(1);

        tokenIn = new MockERC20("Input", "IN", 18);

        callerPrivateKey = 0xdead;
        ownerPrivateKey = 0xbeef;
        whitelistedCaller = vm.addr(callerPrivateKey);
        owner = vm.addr(ownerPrivateKey);

        permit2 = IPermit2(deployPermit2());

        reactor = new RelayOrderReactor(permit2);
        executor = new RelayOrderExecutor(whitelistedCaller, IRelayOrderReactor(reactor), owner);
    }

    function testExecutorWithdrawERC20() public {
        address recipient = vm.addr(0x1);
        tokenIn.mint(address(executor), ONE);
        assertEq(tokenIn.balanceOf(address(executor)), ONE);
        assertEq(tokenIn.balanceOf(recipient), 0);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = tokenIn;

        vm.prank(owner);
        executor.withdrawERC20(tokens, recipient);
        assertEq(tokenIn.balanceOf(address(executor)), 0);
        assertEq(tokenIn.balanceOf(recipient), ONE);
    }

    function testExecutorWithdrawERC20NotOwner() public {
        address recipient = vm.addr(0x1);
        tokenIn.mint(address(executor), ONE);
        assertEq(tokenIn.balanceOf(address(executor)), ONE);
        assertEq(tokenIn.balanceOf(recipient), 0);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = tokenIn;

        vm.prank(vm.addr(0xdeadbeef));
        vm.expectRevert("UNAUTHORIZED");
        executor.withdrawERC20(tokens, recipient);
    }

    function testExecutorWithdrawETH() public {
        address recipient = vm.addr(0x1);
        vm.deal(address(executor), ONE);

        vm.prank(owner);
        executor.withdrawETH(recipient);
        assertEq(address(executor).balance, 0);
        assertEq(recipient.balance, ONE);
    }

    function testExecutorWithdrawETHNotOwner() public {
        address recipient = vm.addr(0x1);
        vm.deal(address(executor), ONE);

        vm.prank(vm.addr(0xdeadbeef));
        vm.expectRevert("UNAUTHORIZED");
        executor.withdrawETH(recipient);
    }

    // caller has permissions required to call all functions in multicall
    function testExecutorMulticallAllPerms() public {
        address recipient = vm.addr(0x1);
        tokenIn.mint(address(executor), ONE);
        vm.deal(address(executor), ONE);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = tokenIn;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(RelayOrderExecutor.withdrawERC20.selector, tokens, recipient);
        data[1] = abi.encodeWithSelector(RelayOrderExecutor.withdrawETH.selector, recipient);

        vm.prank(owner);
        executor.multicall(data);
        assertEq(tokenIn.balanceOf(address(executor)), 0);
        assertEq(tokenIn.balanceOf(recipient), ONE);
        assertEq(address(executor).balance, 0);
        assertEq(recipient.balance, ONE);
    }

    // caller is authorized to call some of the functions but not all
    // in this case, owner can withdraw but not call execute
    function testExecutorMulticallMixedPerms() public {
        address recipient = vm.addr(0x1);
        tokenIn.mint(address(executor), ONE);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = tokenIn;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(RelayOrderExecutor.withdrawERC20.selector, tokens, recipient);
        data[1] = abi.encodeWithSelector(RelayOrderExecutor.execute.selector, SignedOrder("", ""));

        vm.prank(owner);
        vm.expectRevert(RelayOrderExecutor.CallerNotWhitelisted.selector);
        executor.multicall(data);
    }

    // caller has no permissions to call any functions within the multicall
    function testExecutorMulticallMissingPerms() public {
        address recipient = vm.addr(0x1);
        tokenIn.mint(address(executor), ONE);
        vm.deal(address(executor), ONE);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = tokenIn;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(RelayOrderExecutor.withdrawERC20.selector, tokens, recipient);
        data[1] = abi.encodeWithSelector(RelayOrderExecutor.withdrawETH.selector, recipient);

        vm.prank(vm.addr(0xdeadbeef));
        vm.expectRevert("UNAUTHORIZED");
        executor.multicall(data);
    }
}