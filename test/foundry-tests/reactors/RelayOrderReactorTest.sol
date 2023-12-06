// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfoBuilder} from "UniswapX/test/util/OrderInfoBuilder.sol";
import {OrderInfo, SignedOrder} from "UniswapX/src/base/ReactorStructs.sol";
import {ArrayBuilder} from "UniswapX/test/util/ArrayBuilder.sol";
import {MockERC20} from "UniswapX/test/util/mock/MockERC20.sol";
import {CurrencyLibrary} from "UniswapX/src/lib/CurrencyLibrary.sol";
import {InputTokenWithRecipient, ResolvedRelayOrder} from "../../../src/base/ReactorStructs.sol";
import {RelayOrderLib, RelayOrder} from "../../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../../src/reactors/RelayOrderReactor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract RelayOrderReactorTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    MockValidationContract additionalValidationContract;
    IPermit2 permit2;
    RelayOrderReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;

    function setUp() {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

    
    }
}