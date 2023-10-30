import { hdkey } from 'ethereumjs-wallet'
import { ethers, providers } from 'ethers'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const bip39 = require('bip39')

const NETWORK = process.env.NETWORK || 'ganache'
const API_ENDPOINT = process.env.API_ENDPOINT || ''
const PRIVATE_KEY = process.env.PRIVATE_KEY || ''
const POLYGON_RPC_URL = process.env.POLYGON_RPC

const MNEMONIC =
  'bubble addict master water gorilla shoot private tell life skull patch pottery'

const URL = () => {
  if (NETWORK === 'astar')
    return `https://astar-api.bwarelabs.com/${API_ENDPOINT}`
  return 'http://localhost:7545'
}

export const isLocal = () => NETWORK === 'ganache' || NETWORK === 'hardhat'

export const provider = new providers.JsonRpcProvider(URL())
const seed = bip39.mnemonicToSeedSync(MNEMONIC)
const hdk = hdkey.fromMasterSeed(seed)

export const createWallet = (salt: number) => {
  const addrNode = hdk.derivePath(`m/44'/60'/0'/0/${salt}`)
  const privKey = addrNode.getWallet().getPrivateKey()
  const wallet = new ethers.Wallet(privKey, provider)
  return wallet
}

export const createWalletFromPK = () => {
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider)
  return wallet
}

export const getWallet = (salt: number) => {
  if (isLocal()) {
    return createWallet(salt)
  }
  return createWalletFromPK()
}

export const getChainId = async () => (await provider.getNetwork()).chainId

export const gasLimit = () => {
  if (NETWORK === 'mumbai') return 10000000
  if (NETWORK === 'rinkeby') return 20000000
  if (NETWORK === 'polygon') return 10000000
  return 4500000
}

type Option = {
  value: ethers.BigNumber
}
export const option = (props?: Option) => {
  return {
    gasLimit: gasLimit(),
    value: props?.value ? props.value : 0,
  }
}
