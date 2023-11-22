import hre from 'hardhat'
import { expect } from 'chai'
import {SwapRouter, UniswapTrade} from "@uniswap/universal-router-sdk";
import {Pool, Route as RouteV3, Trade as V3Trade} from "@uniswap/v3-sdk";
import { CurrencyAmount, TradeType } from '@uniswap/sdk-core';
import { DAI, FEE_AMOUNT, USDC, buildTrade, getPool, swapOptions } from './shared/uniswapData';
import { DEFAULT_FORK_BLOCK, TEST_RECIPIENT_ADDRESS } from './shared/mainnetForkHelpers';
import { hexToDecimalString } from './shared/hexToDecimalString';
import { registerFixture } from './shared/writeInterop';
import { expandTo18DecimalsBN, expandTo6DecimalsBN } from './shared/helpers';

const { ethers } = hre

describe("Relay order reactor tests", () => {
    beforeEach(async () => {
    })

    let DAI_USDC_V3: Pool;
    let USDC_DAI_V3: Pool

    beforeEach(async () => {
        DAI_USDC_V3 = await getPool(DAI, USDC, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
        USDC_DAI_V3 = await getPool(USDC, DAI, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
    });

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

    it("recipient is not reactor", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([DAI_USDC_V3], DAI, USDC),
            CurrencyAmount.fromRawAmount(DAI, expandTo18DecimalsBN(100).toString()),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({
            recipient: "0x00000000000000000000000000000000DeaDBeef"
        })
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_DAI_USDC_RECIPIENT_NOT_REACTOR', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });
})