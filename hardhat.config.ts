import '@nomiclabs/hardhat-waffle'
import dotenv from 'dotenv'
import fs from 'fs'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'
import 'hardhat-deploy'
import 'hardhat-deploy-ethers'
import 'hardhat-gas-reporter'
import 'hardhat-typechain'
import { HardhatUserConfig } from 'hardhat/types/config'
import './src/tasks/deploy_contracts'

const NETWORK = process.env.NETWORK || ''
const envFilePath = `.env.${NETWORK}`
dotenv.config(fs.existsSync(envFilePath) ? { path: `.env.${NETWORK}` } : {})

const API_ENDPOINT = process.env.API_ENDPOINT || ''
const PRIVATE_KEY = process.env.PRIVATE_KEY || ''
const gasPrice = 30000000000 // 30 gwei
const COINMARKETCAP = process.env.COINMARKETCAP || ''

const networkConfig = (network: string) => {
  switch (network) {
    case 'astar':
      return {
        astar: {
          chainId: 592,
          url: `https://astar-api.bwarelabs.com/${API_ENDPOINT}`,
          accounts: [`0x${PRIVATE_KEY}`],
          gasPrice,
        },
      }
    case 'shiden':
      return {
        shiden: {
          chainId: 336,
          url: `https://shiden-api.bwarelabs.com//${API_ENDPOINT}`,
          accounts: [`0x${PRIVATE_KEY}`],
          gasPrice,
        },
      }
    default:
      return {}
  }
}

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  paths: {
    artifacts: 'build/artifacts',
    cache: 'build/cache',
    deploy: 'src/deploy',
    sources: 'contracts',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    hardhat: {
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: true,
      mining: {
        auto: true,
        interval: 0,
      },
      gasPrice: gasPrice,
    },
    ganache: {
      url: 'http://0.0.0.0:8545',
    },
    ...networkConfig(NETWORK),
  },
  gasReporter: {
    enabled: true,
    currency: 'JPY',
    gasPrice: 20,
    coinmarketcap: COINMARKETCAP,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v5',
  },
}
export default config
