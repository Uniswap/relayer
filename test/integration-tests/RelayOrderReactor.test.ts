import hre from 'hardhat'
import { expect } from 'chai'
import {SwapRouter, UniswapTrade} from "@uniswap/universal-router-sdk";
import {Pool, Route as RouteV3, Trade as V3Trade} from "@uniswap/v3-sdk";
import { CurrencyAmount, TradeType } from '@uniswap/sdk-core';
import { DAI, FEE_AMOUNT, USDC, buildTrade, getPool, swapOptions } from './shared/uniswapData';
import { DEFAULT_FORK_BLOCK } from './shared/mainnetForkHelpers';
import { hexToDecimalString } from './shared/hexToDecimalString';
import { registerFixture } from './shared/writeInterop';

const { ethers } = hre

describe("Relay order reactor tests", () => {
    beforeEach(async () => {
    })

    let DAI_USDC_V3: Pool;

    beforeEach(async () => {
        DAI_USDC_V3 = await getPool(DAI, USDC, FEE_AMOUNT, DEFAULT_FORK_BLOCK);
    });

    it("basic v3 swap", async () => {
        const trade = await V3Trade.fromRoute(
            new RouteV3([DAI_USDC_V3], DAI, USDC),
            CurrencyAmount.fromRawAmount(DAI, '100'),
            TradeType.EXACT_INPUT
        )
        const opts = swapOptions({})
        const methodParameters = SwapRouter.swapCallParameters(new UniswapTrade(buildTrade([trade]), opts))
        registerFixture('_UNISWAP_V3_DAI_USDC', methodParameters)
        expect(hexToDecimalString(methodParameters.value)).to.eq('0')
    });
})