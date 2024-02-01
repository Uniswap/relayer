// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test, stdJson} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {ResolvedRelayOrder, Input, OrderInfo} from "../../../src/base/ReactorStructs.sol";
import {IRelayOrderReactor} from "../../../src/interfaces/IRelayOrderReactor.sol";
import {ReactorEvents} from "../../../src/base/ReactorEvents.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {MethodParameters, Interop} from "../util/Interop.sol";
import {AddressBuilder} from "permit2/test/utils/AddressBuilder.sol";
import {AmountBuilder} from "permit2/test/utils/AmountBuilder.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract RelayOrderReactorIntegrationTest is GasSnapshot, Test, Interop, PermitSignature {
    using stdJson for string;
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;
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

        deployCodeTo("RelayOrderReactor.sol", abi.encode(PERMIT2, UNIVERSAL_ROUTER), RELAY_ORDER_REACTOR);
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

    function testExecute() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = USDC;

        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(tokenIn), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] = Input({
            token: address(gasToken),
            startAmount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 95 * USDC_ONE;

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");
        actions[0] = methodParameters.data;

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecute");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecute");
        reactor.execute(signedOrder);
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

    // Testing the best case for gas benchmarking purposes
    // - input tokens are the same
    // - dirty write for P2 nonce
    // - filler has dust of input token
    function testExecuteSameToken() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = DAI;
        // Fund fillers some dust to get dirty writes
        vm.prank(WHALE);
        gasToken.transfer(filler, 1);
        // simulate that nonce 0 has already been used
        vm.prank(swapper);
        PERMIT2.invalidateUnorderedNonces(0x00, 0x01);

        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(tokenIn), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] = Input({token: address(gasToken), startAmount: 10 * ONE, maxAmount: 10 * ONE, recipient: address(0)});

        uint256 amountOutMin = 95 * USDC_ONE;

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");
        actions[0] = methodParameters.data;

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteSameToken");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteSameToken");
        reactor.execute(signedOrder);
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

    // Testing the average case for gas benchmarking purposes
    // - dirty write for P2 nonce
    // - filler has dust of input token
    function testExecuteAverageCase() public {
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

        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(tokenIn), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] = Input({
            token: address(gasToken),
            startAmount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        uint256 amountOutMin = 95 * USDC_ONE;

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");
        actions[0] = methodParameters.data;

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);
        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteAverageCase");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteAverageCase");
        reactor.execute(signedOrder);
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

    // - filler has NO dust of input token
    // - new nonce used in P2 (clean write)
    function testExecuteWorstCase() public {
        ERC20 tokenIn = DAI;
        ERC20 tokenOut = USDC;
        ERC20 gasToken = USDC;
        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(tokenIn), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] = Input({
            token: address(gasToken),
            startAmount: 10 * USDC_ONE,
            maxAmount: 10 * USDC_ONE,
            recipient: address(0)
        });

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 0,
            deadline: block.timestamp + 100
        });

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_USDC");
        actions[0] = methodParameters.data;

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        _snapshotClassicSwapCall(tokenIn, 100 * ONE, methodParameters, "testExecuteWorstCase");
        _checkpointBalances(swapper, filler, tokenIn, tokenOut, gasToken);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecuteWorstCase");
        reactor.execute(signedOrder);
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

    function testPermitAndExecute() public {
        // this swapper has not yet approved the P2 contract
        // so we will relay a USDC 2612 permit to the P2 contract first
        // making a USDC -> DAI swap
        Input[] memory inputs = new Input[](2);
        inputs[0] = Input({
            token: address(USDC),
            startAmount: 100 * USDC_ONE,
            maxAmount: 100 * USDC_ONE,
            recipient: UNIVERSAL_ROUTER
        });
        inputs[1] =
            Input({token: address(USDC), startAmount: 10 * USDC_ONE, maxAmount: 10 * USDC_ONE, recipient: address(0)});

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

        bytes memory permitData =
            abi.encode(swapper2, address(PERMIT2), type(uint256).max - 1, type(uint256).max - 1, v, r, s);

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_USDC_DAI_SWAPPER2");
        actions[0] = methodParameters.data;
        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper2,
            nonce: 0,
            deadline: block.timestamp + 100
        });

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapper2PrivateKey, address(PERMIT2), order));

        // build multicall data
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(reactor.permit.selector, address(USDC), permitData);
        data[1] = abi.encodeWithSelector(reactor.execute.selector, signedOrder);

        ERC20 tokenIn = USDC;
        ERC20 tokenOut = DAI;
        _checkpointBalances(swapper2, filler, tokenIn, tokenOut, USDC);
        // TODO: This snapshot should always pull tokens in from permit2 and then expose an option to benchmark it with an an allowance on the UR vs. without.
        // For this test, we should benchmark that the user has not permitted permit2, and also has not approved the UR.
        _snapshotClassicSwapCall(tokenIn, 100 * USDC_ONE, methodParameters, "testPermitAndExecute");

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testPermitAndExecute");
        reactor.multicall(data);
        snapEnd();

        assertEq(tokenIn.balanceOf(UNIVERSAL_ROUTER), routerInputBalanceStart, "No leftover input in router");
        assertEq(tokenOut.balanceOf(UNIVERSAL_ROUTER), routerOutputBalanceStart, "No leftover output in reactor");
        assertEq(tokenOut.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        // swapper must have spent 100 USDC for the swap and 10 USDC for gas
        uint256 swapInput = 100 * USDC_ONE;
        uint256 gasPaymentInInput = 10 * USDC_ONE;
        assertEq(
            tokenIn.balanceOf(swapper2),
            swapperInputBalanceStart - swapInput - gasPaymentInInput,
            "Swapper input tokens"
        );
        uint256 amountOutMin = 95 * ONE;
        assertGe(
            tokenOut.balanceOf(swapper2),
            swapperOutputBalanceStart + amountOutMin,
            "Swapper did not receive enough output"
        );
        assertEq(tokenIn.balanceOf(filler), fillerGasInputBalanceStart + 10 * USDC_ONE, "executor balance");
    }

    // Testing a basic relay order where the swap's output is native ETH
    function testExecuteWithNativeAsOutput() public {
        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(DAI), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] =
            Input({token: address(USDC), startAmount: 10 * USDC_ONE, maxAmount: 10 * USDC_ONE, recipient: address(0)});

        uint256 amountOutMin = 51651245170979377; // with 5% slipapge at forked block

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters = readFixture(json, "._UNISWAP_V3_DAI_ETH");
        actions[0] = methodParameters.data;

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 0,
            deadline: block.timestamp + 100
        });
        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

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
        reactor.execute(signedOrder);
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

    // in the case wehre the swapper incorrectly sets the recipient to an address that is not theirs, but the
    // calldata includes a SWEEP back to them which should cause the transaction to revert
    function testExecuteDoesNotSucceedIfReactorIsRecipientAndUniversalRouterSweep() public {
        Input[] memory inputs = new Input[](2);
        inputs[0] =
            Input({token: address(DAI), startAmount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputs[1] =
            Input({token: address(USDC), startAmount: 10 * USDC_ONE, maxAmount: 10 * USDC_ONE, recipient: address(0)});

        bytes[] memory actions = new bytes[](1);
        MethodParameters memory methodParameters =
            readFixture(json, "._UNISWAP_V3_DAI_USDC_RECIPIENT_REACTOR_WITH_SWEEP");
        actions[0] = methodParameters.data;

        OrderInfo memory info = OrderInfo({
            reactor: IRelayOrderReactor(address(reactor)),
            swapper: swapper,
            nonce: 0,
            deadline: block.timestamp + 100
        });

        RelayOrder memory order = RelayOrder({
            info: info,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            actions: actions,
            inputs: inputs
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.prank(filler);
        vm.expectRevert(0x675cae38); // InvalidToken()
        reactor.execute(signedOrder);
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
