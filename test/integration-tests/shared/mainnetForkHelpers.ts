import { UNIVERSAL_ROUTER_ADDRESS } from '@uniswap/universal-router-sdk'
import hre from 'hardhat'

export const DEFAULT_FORK_BLOCK = 15360000;
export const MAINNET_ROUTER_ADDRESS = UNIVERSAL_ROUTER_ADDRESS(1)
export const FORGE_ROUTER_ADDRESS = "0x378718523232A14BE8A24e291b5A5075BE04D121";
export const TEST_RECIPIENT_ADDRESS = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

export const resetFork = async (block: number = DEFAULT_FORK_BLOCK) => {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
          blockNumber: block,
        },
      },
    ],
  })
}
