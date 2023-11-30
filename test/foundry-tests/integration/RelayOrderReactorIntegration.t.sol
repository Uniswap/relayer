// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test, stdJson} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {OrderInfo, SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {InputTokenWithRecipient, ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../../src/base/ReactorEvents.sol";
import {CurrencyLibrary} from "../../../src/lib/CurrencyLibrary.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {PermitExecutor} from "../../../src/sample-executors/PermitExecutor.sol";
import {MethodParameters, Interop} from "../util/Interop.sol";

contract RelayOrderReactorIntegrationTest is GasSnapshot, Test, Interop, PermitSignature {
    using stdJson for string;
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    uint256 constant ONE = 10 ** 18;
    uint256 constant USDC_ONE = 10 ** 6;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;
    address constant UNIVERSAL_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address payable constant RELAY_ORDER_REACTOR = payable(0x378718523232A14BE8A24e291b5A5075BE04D121);

    uint256 swapperPrivateKey;
    uint256 swapper2PrivateKey;
    address swapper;
    address swapper2;
    address filler;
    RelayOrderReactor reactor;
    PermitExecutor permitExecutor;
    string json;

    error InvalidNonce();
    error InvalidSigner();

    uint256 swapperInputBalanceStart;
    uint256 swapperOutputBalanceStart;
    uint256 routerInputBalanceStart;
    uint256 routerOutputBalanceStart;
    uint256 fillerGasInputBalanceStart;

    function setUp() public {
        swapperPrivateKey = 0xbabe;
        swapper = vm.addr(swapperPrivateKey);
        swapper2PrivateKey = 0xbeef;
        swapper2 = vm.addr(swapper2PrivateKey);
        filler = makeAddr("filler");
        string memory root = vm.projectRoot();
        json = vm.readFile(string.concat(root, "/test/foundry-tests/interop.json"));
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 17972788);

        deployCodeTo("RelayOrderReactor.sol", abi.encode(PERMIT2, UNIVERSAL_ROUTER), RELAY_ORDER_REACTOR);
        reactor = RelayOrderReactor(RELAY_ORDER_REACTOR);
        permitExecutor = new PermitExecutor(address(filler), reactor, address(filler));

        // Swapper max approves permit post for all input tokens
        vm.startPrank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);
        USDC.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(DAI), address(reactor), type(uint160).max, type(uint48).max);
        PERMIT2.approve(address(USDC), address(reactor), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // Fund swappers
        vm.startPrank(WHALE);
        DAI.transfer(swapper, 1000 * ONE);
        DAI.transfer(swapper2, 1000 * ONE);
        USDC.transfer(swapper, 1000 * USDC_ONE);
        USDC.transfer(swapper2, 1000 * USDC_ONE);
        vm.stopPrank();

        // initial assumptions
        assertEq(USDC.balanceOf(address(reactor)), 0, "reactor should have no USDC");
        assertEq(DAI.balanceOf(address(reactor)), 0, "reactor should have no DAI");
    }

    // swapper creates one order containing a universal router swap for 100 DAI -> USDC
    // order contains two inputs: DAI for the swap and USDC as gas payment for fillers
    // at the forked block, 95276229 is the minAmountOut
    function testExecute() public {
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] =
            InputTokenWithRecipient({token: DAI, amount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputTokens[1] = InputTokenWithRecipient({
            token: USDC,
            amount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 95 * USDC_ONE;

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");
        actions[0] = abi.encode(UNIVERSAL_ROUTER, methodParameters.value, methodParameters.data);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputTokens
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        _checkpointBalances(swapper, filler, tokenIn, tokenOut, USDC);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecute");
        reactor.execute{value: methodParameters.value}(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(tokenOut.balanceOf(UNIVERSAL_ROUTER), routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(tokenOut.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        assertEq(tokenIn.balanceOf(swapper), swapperInputBalanceStart - 100 * ONE, "Swapper input tokens");
        assertGe(
            tokenOut.balanceOf(swapper),
            swapperOutputBalanceStart + amountOutMin - 10 * USDC_ONE,
            "Swapper did not receive enough output"
        );
        assertEq(tokenOut.balanceOf((filler)), fillerGasInputBalanceStart + 10 * USDC_ONE, "filler balance");
    }

    function testPermitAndExecute() public {
        // this swapper has not yet approved the P2 contract
        // so we will relay a USDC 2612 permit to the P2 contract first
        // making a USDC -> DAI swap
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] = InputTokenWithRecipient({
            token: USDC,
            amount: 100 * USDC_ONE,
            maxAmount: 100 * USDC_ONE,
            recipient: UNIVERSAL_ROUTER
        });
        inputTokens[1] = InputTokenWithRecipient({
            token: USDC,
            amount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 95 * ONE;

        // sign permit for USDC
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                USDC.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        swapper2,
                        address(PERMIT2),
                        type(uint256).max - 1, // infinite approval
                        USDC.nonces(swapper2),
                        type(uint256).max - 1 // infinite deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapper2PrivateKey, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(signer, swapper2);

        bytes memory permitData = abi.encode(
            address(USDC), abi.encode(swapper2, address(PERMIT2), type(uint256).max - 1, type(uint256).max - 1, v, r, s)
        );

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_USDC_DAI");
        actions[0] = abi.encode(UNIVERSAL_ROUTER, methodParameters.value, methodParameters.data);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputTokens
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapper2PrivateKey, address(PERMIT2), order));

        ERC20 tokenIn = USDC;
        ERC20 tokenOut = DAI;
        // in this case, gas payment will go to executor (msg.sender)
        _checkpointBalances(swapper2, address(permitExecutor), tokenIn, tokenOut, USDC);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testPermitAndExecute");
        permitExecutor.executeWithPermit{value: methodParameters.value}(signedOrder, permitData);
        snapEnd();

        assertEq(tokenIn.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(tokenOut.balanceOf(UNIVERSAL_ROUTER), routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(tokenOut.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        // swapper must have spent 100 USDC for the swap and 10 USDC for gas
        assertEq(
            tokenIn.balanceOf(swapper2),
            swapperInputBalanceStart - 100 * USDC_ONE - 10 * USDC_ONE,
            "Swapper input tokens"
        );
        assertGe(
            tokenOut.balanceOf(swapper2),
            swapperOutputBalanceStart + amountOutMin,
            "Swapper did not receive enough output"
        );
        assertEq(
            tokenIn.balanceOf(address(permitExecutor)), fillerGasInputBalanceStart + 10 * USDC_ONE, "executor balance"
        );
    }

    // swapper creates one order containing a universal router swap for 100 DAI -> ETH
    // order contains two inputs: DAI for the swap and USDC as gas payment for fillers
    // at the forked block, X is the minAmountOut
    function testExecuteWithNativeAsOutput() public {
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] =
            InputTokenWithRecipient({token: DAI, amount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputTokens[1] = InputTokenWithRecipient({
            token: USDC,
            amount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 51651245170979377; // with 5% slipapge at forked block

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_ETH");
        actions[0] = abi.encode(UNIVERSAL_ROUTER, methodParameters.value, methodParameters.data);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputTokens
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        ERC20 tokenIn = DAI;
        swapperInputBalanceStart = tokenIn.balanceOf(swapper);
        swapperOutputBalanceStart = swapper.balance;
        routerInputBalanceStart = tokenIn.balanceOf(UNIVERSAL_ROUTER);
        routerOutputBalanceStart = UNIVERSAL_ROUTER.balance;
        fillerGasInputBalanceStart = USDC.balanceOf(filler);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteWithNativeAsOutput");
        reactor.execute{value: methodParameters.value}(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(UNIVERSAL_ROUTER.balance, routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(address(reactor).balance, 0, "No leftover output in reactor");
        assertEq(tokenIn.balanceOf(swapper), swapperInputBalanceStart - 100 * ONE, "Swapper input tokens");
        assertGe(
            swapper.balance,
            swapperOutputBalanceStart + amountOutMin - 10 * USDC_ONE,
            "Swapper did not receive enough output"
        );
        assertEq(USDC.balanceOf(filler), fillerGasInputBalanceStart + 10 * USDC_ONE, "filler balance");
    }

    function testExecuteFailsIfReactorIsNotRecipient() public {
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] =
            InputTokenWithRecipient({token: DAI, amount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputTokens[1] = InputTokenWithRecipient({
            token: USDC,
            amount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 95 * USDC_ONE;

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC_RECIPIENT_NOT_REACTOR");
        actions[0] = abi.encode(UNIVERSAL_ROUTER, methodParameters.value, methodParameters.data);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputTokens
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.prank(filler);
        vm.expectRevert(CurrencyLibrary.InsufficientBalance.selector);
        reactor.execute{value: methodParameters.value}(signedOrder);
    }

    function _checkpointBalances(address _swapper, address _filler, ERC20 tokenIn, ERC20 tokenOut, ERC20 gasInput)
        internal
    {
        swapperInputBalanceStart = tokenIn.balanceOf(_swapper);
        swapperOutputBalanceStart = tokenOut.balanceOf(_swapper);
        routerInputBalanceStart = tokenIn.balanceOf(UNIVERSAL_ROUTER);
        routerOutputBalanceStart = tokenOut.balanceOf(UNIVERSAL_ROUTER);
        fillerGasInputBalanceStart = gasInput.balanceOf(_filler);
    }
}
