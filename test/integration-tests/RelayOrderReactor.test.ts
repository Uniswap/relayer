import { expect } from 'chai'
import { SwapRouter, UniswapTrade} from "@uniswap/universal-router-sdk";
import {FeeAmount, Pool, Route as RouteV3, Trade as V3Trade} from "@uniswap/v3-sdk";
import { CurrencyAmount, Ether, TradeType } from '@uniswap/sdk-core';
import { DAI, FEE_AMOUNT, USDC, WETH, buildTrade, getPool, swapOptions } from './shared/uniswapData';
import { DEFAULT_FORK_BLOCK, FORGE_ROUTER_ADDRESS, FORGE_SWAPPER2_ADDRESS, FORGE_SWAPPER_ADDRESS } from './shared/mainnetForkHelpers';
import { hexToDecimalString } from './shared/hexToDecimalString';
import { registerFixture } from './shared/writeInterop';
import { expandTo18DecimalsBN, expandTo6DecimalsBN } from './shared/helpers';
import { CommandType, RoutePlanner } from '@uniswap/universal-router-sdk';
import { SOURCE_ROUTER } from './shared/constants';
import { encodePath } from './shared/swapRouter02Helpers';

describe("Relay order reactor tests", () => {
    let DAI_USDC_V3: Pool;
    let USDC_DAI_V3: Pool;
    let DAI_WETH_V3: Pool;

    beforeEach(async () => {
        DAI_USDC_V3 = await getPool(DAI, USDC, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
        USDC_DAI_V3 = await getPool(USDC, DAI, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
        DAI_WETH_V3 = await getPool(DAI, WETH, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
    });

    /*
        Guidelines for relay orders
        - ROUTER pays (payerIsUser = false)
        - recipient is user
        - unless, routerMustCustody then we add sweep
    */
    it("basic v3 swap, DAI -> USDC", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([DAI_USDC_V3], DAI, USDC),
            CurrencyAmount.fromRawAmount(DAI, expandTo18DecimalsBN(100).toString()),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({})
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_DAI_USDC', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });

    it("basic v3 swap, USDC -> DAI", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([USDC_DAI_V3], USDC, DAI),
            CurrencyAmount.fromRawAmount(USDC, expandTo6DecimalsBN(100).toString()),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({})
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_USDC_DAI', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });

    it("basic v3 swap, USDC -> DAI swapper2", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([USDC_DAI_V3], USDC, DAI),
            CurrencyAmount.fromRawAmount(USDC, expandTo6DecimalsBN(100).toString()),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({
            recipient: FORGE_SWAPPER2_ADDRESS
        })
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_USDC_DAI_SWAPPER2', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });

    it("basic v3 swap to native, DAI -> ETH", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([DAI_WETH_V3], DAI, Ether.onChain(1)),
            CurrencyAmount.fromRawAmount(DAI, expandTo18DecimalsBN(100).toString()),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({})
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_DAI_ETH', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });

    it("recipient is reactor not user", async () => {
        const planner = (new RoutePlanner());
        planner.addCommand(CommandType.V3_SWAP_EXACT_IN, [
            FORGE_ROUTER_ADDRESS, // not swapper
            expandTo18DecimalsBN(100),
            expandTo6DecimalsBN(95),
            encodePath([DAI.address, USDC.address], [FeeAmount.MEDIUM]),
            SOURCE_ROUTER
        ])
        planner.addCommand(CommandType.SWEEP, [
            USDC.address,
            FORGE_SWAPPER_ADDRESS,
            expandTo6DecimalsBN(95)
        ])
        const { commands, inputs } = planner;
        const methodParameters = {
            calldata: SwapRouter.INTERFACE.encodeFunctionData('execute(bytes,bytes[])', [commands, inputs]),
            value: '0x0',
        }
        registerFixture('_UNISWAP_V3_DAI_USDC_RECIPIENT_REACTOR_WITH_SWEEP', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });
})