import { parseEther } from 'ethers/lib/utils'
import { ethers } from 'hardhat'
import { Erc20 } from '../types/Erc20'
import { Erc20Factory } from '../types/Erc20Factory'
import { LToken } from '../types/LToken'
import { LTokenFactory } from '../types/LTokenFactory'
import { LendingPool } from '../types/LendingPool'
import { LendingPoolFactory } from '../types/LendingPoolFactory'
import { Leverager } from '../types/Leverager'
import { LeveragerFactory } from '../types/LeveragerFactory'
describe('leverager', async () => {
  let usdc: Erc20
  let lUSDC: LToken
  let woas: Erc20
  let LP: LendingPool
  let LV: Leverager
  let oracle
  beforeEach(async () => {
    const [dominator, user] = await ethers.getSigners()

    usdc = await new Erc20Factory(user).deploy(
      'USDC',
      'USDC',
      user.address,
      parseEther('1000')
    )
    woas = await new Erc20Factory(user).deploy(
      'WOAS',
      'WOAS',
      dominator.address,
      parseEther('100')
    )
    lUSDC = await new LTokenFactory(user).deploy('lUSDC', 'lUSDC')

    oracle = await (
      await ethers.getContractFactory(
        'contracts/mocks/PriceOracle.sol:PriceOracle'
      )
    ).deploy()
    await oracle.deployed()
    LP = await new LendingPoolFactory(user).deploy(usdc.address, lUSDC.address)
    LV = await new LeveragerFactory(user).deploy()
    await LV.initialize(LP.address, woas.address, oracle.address)
  })
  it('loop', async function () {
    const [, user] = await ethers.getSigners()
    console.log('ltv is %s', await LV.ltv(usdc.address))
    await usdc.connect(user).approve(LV.address, parseEther('1000'))

    await LV.connect(user).loop(usdc.address, parseEther('100'), 2, 8000, 10)
    console.log('totalDposit is %s', await LP.totalDeposit(usdc.address))
    console.log('totalBorrow is %s', await LP.totalBorrow(usdc.address))
  })
})
