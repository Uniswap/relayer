// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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
    uint256 fillerPrivateKey;
    address filler;
    uint256 executorOwnerPrivateKey;
    address executorOwner;

    RelayOrderExecutor executor;

    function setUp() public {
        vm.chainId(1);

        tokenIn = new MockERC20("Input", "IN", 18);

        fillerPrivateKey = 0xdead;
        executorOwnerPrivateKey = 0xbeef;
        filler = vm.addr(fillerPrivateKey);
        executorOwner = vm.addr(executorOwnerPrivateKey);

        permit2 = IPermit2(deployPermit2());

        reactor = new RelayOrderReactor(permit2);
        executor = new RelayOrderExecutor(filler, IRelayOrderReactor(reactor), executorOwner);
    }

    // Test:
    // - Executor has ERC20 balance, can withdraw
    // - Executor has ETH balance, can withdraw
    // - Perms setup
    // - Multicall, permit + execute
}
