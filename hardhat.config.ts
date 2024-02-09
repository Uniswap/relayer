import 'hardhat-typechain'
import '@nomiclabs/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import dotenv from 'dotenv'
dotenv.config()

const DEFAULT_COMPILER_SETTINGS = {
  version: '0.8.24',
  settings: {
    viaIR: true,
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 1_000_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

export default {
  paths: {
    sources: './src',
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      chainId: 1,
      forking: {
        url: `${process.env.FOUNDRY_RPC_URL}`,
        blockNumber: 15360000,
      },
    },
    mainnet: {
      url: `${process.env.FOUNDRY_RPC_URL}`,
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
  },
  mocha: {
    timeout: 60000,
  },
}
