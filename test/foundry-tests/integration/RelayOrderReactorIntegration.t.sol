// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test, stdJson} from "forge-std/Test.sol";
import {AddressBuilder} from "permit2/test/utils/AddressBuilder.sol";
import {AmountBuilder} from "permit2/test/utils/AmountBuilder.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {Input, OrderInfo, FeeEscalator} from "../../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../../src/base/ReactorEvents.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InputBuilder} from "../util/InputBuilder.sol";
import {RelayOrderBuilder} from "../util/RelayOrderBuilder.sol";
import {FeeEscalatorBuilder} from "../util/FeeEscalatorBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MethodParameters, Interop} from "../util/Interop.sol";
import {ReactorEvents} from "../../../src/base/ReactorEvents.sol";

contract RelayOrderReactorIntegrationTest is GasSnapshot, Test, Interop, PermitSignature {
    using stdJson for string;
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;
    using InputBuilder for Input;
    using RelayOrderBuilder for RelayOrder;
    using FeeEscalatorBuilder for FeeEscalator;
    using AddressBuilder for address[];
    using AmountBuilder for uint256[];

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

        deployCodeTo("RelayOrderReactor.sol", abi.encode(UNIVERSAL_ROUTER), RELAY_ORDER_REACTOR);
        reactor = RelayOrderReactor(RELAY_ORDER_REACTOR);

        // Swapper max approves permit post for all input tokens
        vm.startPrank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);
        USDC.approve(address(PERMIT2), type(uint256).max);
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

        (uint160 allowance,,) = PERMIT2.allowance(swapper, address(USDC), address(reactor));
        assertEq(allowance, 0, "reactor must not have allowance for tokens");
        (allowance,,) = PERMIT2.allowance(swapper, address(DAI), address(reactor));
        assertEq(allowance, 0, "reactor must not have approval for tokens");
    }

    /// @notice Tests the "best case" execute:
    /// swap: DAI -> USDC
    /// fee: DAI
    /// Same input and fee token.
    /// Filler balance is nonzero of input token.
    /// P2 nonce is dirty.
    /// Specifies fee recipient. TODO: use msg.sender when supported
    function test_execute_bestCase() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = DAI;
        // Fund fillers some dust to get dirty writes
        vm.prank(WHALE);
        gasToken.transfer(filler, 1);
        // simulate that nonce 0 has already been used
        vm.prank(swapper);
        PERMIT2.invalidateUnorderedNonces(0x00, 0x01);

        Input memory input = InputBuilder.init(tokenIn).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);
        FeeEscalator memory fee = FeeEscalatorBuilder.init(gasToken).withStartAmount(10 * ONE).withEndAmount(10 * ONE);

        uint256 amountOutMin = 95 * USDC_ONE;
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(1);

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteSameToken");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteSameToken");
        reactor.execute(signedOrder, filler);
        snapEnd();

        assertEq(tokenIn.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(tokenOut.balanceOf(UNIVERSAL_ROUTER), routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(tokenOut.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        assertEq(tokenIn.balanceOf(swapper), swapperInputBalanceStart - 100 * ONE - 10 * ONE, "Swapper input tokens");
        assertGe(
            tokenOut.balanceOf(swapper),
            swapperOutputBalanceStart + amountOutMin,
            "Swapper did not receive enough output"
        );
        assertEq(DAI.balanceOf((filler)), fillerGasInputBalanceStart + 10 * ONE, "filler balance");
    }

    /// @notice Tests the "average case" execute:
    /// swap: DAI -> USDC
    /// fee: USDC
    /// Different input and fee token.
    /// Filler balance is nonzero of input token.
    /// P2 nonce is dirty.
    /// Specifies a fee recipient.
    function test_execute_averageCase() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = USDC;
        // Fund fillers some dust to get dirty writes
        /// @dev there are some extra savings from loading the token contract here (~3k) that should be ignored.
        ///      the relative difference vs. classic should be the same though.
        vm.prank(WHALE);
        gasToken.transfer(filler, 1);
        // simulate that nonce 0 has already been used
        vm.prank(swapper);
        PERMIT2.invalidateUnorderedNonces(0x00, 0x01);

        Input memory input = InputBuilder.init(tokenIn).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);

        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(gasToken).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        uint256 amountOutMin = 95 * USDC_ONE;
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(1);

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteAverageCase");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteAverageCase");
        reactor.execute(signedOrder, filler);
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

    /// @notice Tests the "worst case" execute:
    /// swap: DAI -> USDC
    /// fee: USDC
    /// Different input and fee token.
    /// Filler balance is 0 of input token.
    /// Nonce is clean.
    /// Specifies a fee recipient.
    function test_execute_worstCase() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = USDC;

        Input memory input = InputBuilder.init(tokenIn).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);

        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(gasToken).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(0);

        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteWorstCase");
        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteWorstCase");
        reactor.execute(signedOrder, filler);
        snapEnd();

        uint256 amountOutMin = 95 * USDC_ONE;

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

    /// @notice Tests a multicall with a permit and execute.
    /// Permit:
    /// Swapper2 permits PERMIT2 spending on USDC.
    /// Execute:
    /// swap: USDC -> DAI
    /// fee: USDC
    /// Same input and fee token.
    /// Filler balance is 0 of input token.
    /// Nonce is clean.
    /// Specifies a fee recipient.
    function test_multicall_permitAndExecute() public {
        (address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            generatePermitData(address(PERMIT2), USDC, swapper2PrivateKey);

        // this swapper has not yet approved the P2 contract
        // so we will relay a USDC 2612 permit to the P2 contract first
        // making a USDC -> DAI swap
        Input memory input = InputBuilder.init(USDC).withAmount(100 * USDC_ONE).withRecipient(UNIVERSAL_ROUTER);
        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(USDC).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_USDC_DAI_SWAPPER2");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(
            block.timestamp + 100
        ).withNonce(0);

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapper2PrivateKey, address(PERMIT2), order));

        // build multicall data
        bytes[] memory data = new bytes[](2);
        data[0] =
            abi.encodeWithSelector(reactor.permit.selector, address(USDC), swapper2, spender, amount, deadline, v, r, s);
        data[1] = abi.encodeWithSignature("execute((bytes,bytes),address)", signedOrder, filler);

        // TODO: This snapshot should always pull tokens in from permit2 and then expose an option to benchmark it with an an allowance on the UR vs. without.
        // For this test, we should benchmark that the user has not permitted permit2, and also has not approved the UR.
        _snapshotClassicSwapCall(USDC, 100 * USDC_ONE, methodParameters, "testPermitAndExecute");

        _checkpointBalances(swapper2, filler, USDC, DAI, USDC);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testPermitAndExecute");
        reactor.multicall(data);
        snapEnd();

        assertEq(USDC.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(DAI.balanceOf(UNIVERSAL_ROUTER), routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(DAI.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        // swapper must have spent 100 USDC for the swap and 10 USDC for gas
        assertEq(
            USDC.balanceOf(swapper2), swapperInputBalanceStart - 100 * USDC_ONE - 10 * USDC_ONE, "Swapper input tokens"
        );
        assertGe(
            DAI.balanceOf(swapper2),
            swapperOutputBalanceStart + 95 * ONE, // amountOutMin
            "Swapper did not receive enough output"
        );
        assertEq(USDC.balanceOf(filler), fillerGasInputBalanceStart + 10 * USDC_ONE, "executor balance");
    }

    /// @notice Tests execute with a native eth output.
    /// swap: DAI -> ETH
    /// fee: DAI
    /// Same input and fee token.
    /// Filler balance is 0 of input token.
    /// Nonce is clean.
    /// Specifies a fee recipient.
    function test_execute_withNativeOutput() public {
        Input memory input = InputBuilder.init(DAI).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);
        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(USDC).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        uint256 amountOutMin = 51651245170979377; // with 5% slipapge at forked block
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_ETH");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(0);
        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        ERC20 tokenIn = DAI;
        swapperInputBalanceStart = tokenIn.balanceOf(swapper);
        swapperOutputBalanceStart = swapper.balance;
        routerInputBalanceStart = tokenIn.balanceOf(UNIVERSAL_ROUTER);
        routerOutputBalanceStart = UNIVERSAL_ROUTER.balance;
        fillerGasInputBalanceStart = USDC.balanceOf(filler);

        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteWithNativeAsOutput");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteWithNativeAsOutput");
        reactor.execute(signedOrder, filler);
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

    /// @notice Tests that execute reverts in the case where
    // the swapper incorrectly sets the recipient to an address that is not theirs, but the
    // calldata includes a SWEEP back to them which should cause the transaction to revert
    function test_execute_reverts_ifReactorIsRecipientAndUniversalRouterSweep() public {
        Input memory input = InputBuilder.init(DAI).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);
        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(USDC).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        MethodParameters memory methodParameters =
            readFixture(json, "._UNISWAP_V3_DAI_USDC_RECIPIENT_REACTOR_WITH_SWEEP");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(0);

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.prank(filler);
        vm.expectRevert(0x675cae38); // InvalidToken()
        reactor.execute(signedOrder, filler);
    }

    /// @notice Tests execute with a different fee recipient address.
    /// swap: DAI -> USDC
    /// fee: USDC
    /// Different input and fee token.
    /// Filler balance is 0 of input token.
    /// Nonce is clean.
    /// Specifies a fee recipient.
    function test_execute_differentFeeRecipient() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = USDC;

        address feeRecipient = makeAddr("feeRecipient");
        Input memory input = InputBuilder.init(tokenIn).withAmount(100 * ONE).withRecipient(UNIVERSAL_ROUTER);
        FeeEscalator memory fee =
            FeeEscalatorBuilder.init(gasToken).withStartAmount(10 * USDC_ONE).withEndAmount(10 * USDC_ONE);

        uint256 amountOutMin = 95 * USDC_ONE;
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 100
        ).withNonce(1);

        RelayOrder memory order =
            RelayOrderBuilder.init(orderInfo, input, fee).withUniversalRouterCalldata(methodParameters.data);

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteDifferentRecipient");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteDifferentRecipient");
        reactor.execute(signedOrder, feeRecipient);
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
        assertEq(tokenOut.balanceOf((feeRecipient)), 10 * USDC_ONE, "fee recipient balance");
    }

    function test_execute_noActions_noInputs_noFee_succeeds() public {
        FeeEscalator memory fee;
        Input memory input;
        RelayOrder memory order = RelayOrderBuilder.initDefault(USDC, address(reactor), swapper);
        order.input = input;
        order.fee = fee;
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));
        vm.expectEmit(true, true, true, true, address(reactor));
        emit ReactorEvents.Fill(order.hash(), address(this), swapper, order.info.nonce);
        reactor.execute(signedOrder, address(this));
        assertEq(order.universalRouterCalldata.length, 0);
    }

    function test_execute_noActions_noInputs_withFee_succeeds() public {
        // Essentially a relayed transfer.
        Input memory input;
        RelayOrder memory order = RelayOrderBuilder.initDefault(USDC, address(reactor), swapper);
        order.input = input;
        order.fee = order.fee.withStartAmount(USDC_ONE).withEndAmount(USDC_ONE);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit ReactorEvents.Fill(order.hash(), address(filler), swapper, order.info.nonce);

        vm.prank(address(filler));
        reactor.execute(signedOrder, address(filler));
        assertEq(order.universalRouterCalldata.length, 0);
        assertEq(USDC.balanceOf(address(filler)), USDC_ONE);
    }

    function test_execute_noActions_withInputs_withFee_succeeds() public {
        // Even if no universalRouterCalldata are encoded, a transfer of tokens from an Input and a Fee can still happen.
        RelayOrder memory order = RelayOrderBuilder.initDefault(USDC, address(reactor), swapper);
        order.input = order.input.withRecipient(address(this)).withAmount(USDC_ONE);
        order.fee = order.fee.withStartAmount(USDC_ONE).withEndAmount(USDC_ONE);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit ReactorEvents.Fill(order.hash(), address(filler), swapper, order.info.nonce);

        vm.prank(address(filler));
        reactor.execute(signedOrder, address(filler));
        assertEq(order.universalRouterCalldata.length, 0);
        assertEq(USDC.balanceOf(address(filler)), USDC_ONE);
        assertEq(USDC.balanceOf(address(this)), USDC_ONE);
    }

    function test_execute_reverts_withUniversalRouterLengthMismatchError() public {
        Input memory input;
        FeeEscalator memory fee;
        bytes memory commands = bytes("");
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode("randombytes");
        bytes memory universalRouterCalldata =
            abi.encodeWithSelector(bytes4(keccak256("execute(bytes,bytes[])")), commands, inputs);
        RelayOrder memory order = RelayOrderBuilder.initDefault(USDC, address(reactor), swapper);
        order.input = input;
        order.fee = fee;
        order.universalRouterCalldata = universalRouterCalldata;
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));
        vm.expectRevert(bytes4(keccak256("LengthMismatch()")));
        reactor.execute(signedOrder, address(this));
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

    /// @dev Snapshot the gas required for an encoded call
    /// - must be before the reactor execution since pool state will have changed
    /// - since our generated calldata assumes that the router has custody of the tokens, we must transfer them here
    function _snapshotClassicSwapCall(
        ERC20 inputToken,
        uint256 inputAmount,
        MethodParameters memory methodParameters,
        string memory testName
    ) internal {
        uint256 snapshot = vm.snapshot();

        vm.startPrank(swapper);

        snapStart(string.concat("RelayOrderReactorIntegrationTest-", testName, "-ClassicSwap"));
        inputToken.transfer(UNIVERSAL_ROUTER, inputAmount);
        (bool success,) = UNIVERSAL_ROUTER.call(methodParameters.data);
        snapEnd();

        require(success, "call failed");
        vm.stopPrank();

        vm.revertTo(snapshot);
    }
}
