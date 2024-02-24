import { expect } from 'chai'
import { BigNumber } from 'ethers'
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
import { PriceOracle } from '../types/PriceOracle'
import { PriceOracleFactory } from '../types/PriceOracleFactory'
import { VdToken } from '../types/VdToken'
import { VdTokenFactory } from '../types/VdTokenFactory'
import { Weth9 } from '../types/Weth9'
import { Weth9Factory } from '../types/Weth9Factory'
describe('leverager', async () => {
  let usdc: Erc20
  let lUSDC: LToken
  let vdUSDC: VdToken
  let woas: Weth9
  let lwOas: LToken
  let vdOas: VdToken
  let LP: LendingPool
  let LV: Leverager
  let oracle: PriceOracle
  beforeEach(async () => {
    const [, user] = await ethers.getSigners()

    usdc = await new Erc20Factory(user).deploy(
      'USDC',
      'USDC',
      user.address,
      parseEther('1000')
    )
    woas = await new Weth9Factory(user).deploy()
    woas.deposit({ value: parseEther('100') })
    lUSDC = await new LTokenFactory(user).deploy('lUSDC', 'lUSDC')
    vdUSDC = await new VdTokenFactory(user).deploy('vdUSDC', 'vdUSDC')
    lwOas = await new LTokenFactory(user).deploy('lOAS', 'lOAS')
    vdOas = await new VdTokenFactory(user).deploy('vdOAS', 'vdOAS')

    oracle = await new PriceOracleFactory(user).deploy()
    await oracle.deployed()
    LP = await new LendingPoolFactory(user).deploy(
      usdc.address,
      lUSDC.address,
      vdUSDC.address
    )
    await LP.addAsset(woas.address, lwOas.address, vdOas.address)
    LV = await new LeveragerFactory(user).deploy()
    await LV.initialize(LP.address, woas.address, oracle.address)
  })
  describe('loop', async () => {
    it('loop count should be gte to 2', async function () {
      await expect(
        LV.loop(usdc.address, parseEther('100'), 2, 8000, 1)
      ).to.be.revertedWith('Inappropriate loop count')
    })
    it('loop count should be lte to 40', async function () {
      await expect(
        LV.loop(usdc.address, parseEther('100'), 40, 8000, 41)
      ).to.be.revertedWith('Inappropriate loop count')
    })
    it('borrow ratio should be lte to ltv', async function () {
      await expect(
        LV.loop(usdc.address, parseEther('100'), 2, 8001, 2)
      ).to.be.revertedWith('Inappropriate borrow rate')
    })
    it('borrow ratio should be gt 0', async function () {
      await expect(
        LV.loop(usdc.address, parseEther('100'), 2, 0, 2)
      ).to.be.revertedWith('Inappropriate borrow rate')
    })
    it('when user loops 10 times with 1000 usdc with 80% borrw rate', async function () {
      const initial = parseEther('1000')
      const [, user] = await ethers.getSigners()
      await usdc.connect(user).approve(LV.address, initial)
      await LV.connect(user).loop(usdc.address, initial, 2, 8000, 10)

      expect(await lUSDC.balanceOf(await user.getAddress())).to.be.equal(
        totalDepositExpected(10, initial, BigNumber.from('8000'))
      )
      expect(await vdUSDC.balanceOf(await user.getAddress())).to.be.equal(
        totalBorrowExpected(10, initial, BigNumber.from('8000'))
      )
    })
  })
  describe('loopOAS', async function () {
    it('when user loops 10 times with 100 woas with 80% borrw rate', async function () {
      const initial = parseEther('100')
      const [, user] = await ethers.getSigners()
      await woas.connect(user).approve(LV.address, initial)
      await LV.connect(user).loopOAS(2, 8000, 10, {
        value: initial,
      })

      expect(await lwOas.balanceOf(await user.getAddress())).to.be.equal(
        totalDepositExpected(10, initial, BigNumber.from('8000'))
      )
      expect(await vdOas.balanceOf(await user.getAddress())).to.be.equal(
        totalBorrowExpected(10, initial, BigNumber.from('8000'))
      )
    })
  })
  describe('close', async function () {
    it('can close 1000 usdc with 10 loops', async function () {
      const initial = parseEther('100')
      const [, user] = await ethers.getSigners()
      await usdc.connect(user).approve(LV.address, initial)
      await LV.connect(user).loop(usdc.address, initial, 2, 8000, 10)

      await LV.connect(user).close(usdc.address)
      //expect(await lUSDC.balanceOf(await user.getAddress())).to.be.equal(0)
      expect(await vdUSDC.balanceOf(await user.getAddress())).to.be.equal(0)
    })
  })
  describe('ltv', async () => {
    it('ltv can be retrived', async function () {
      const ltv = await LV.ltv(usdc.address)
      expect(ltv).to.be.equal(8000)
    })
  })
})

const depositExpected = (
  loop: number,
  deposit: BigNumber,
  borrowRate: BigNumber
) => {
  if (loop === 0) {
    return deposit
  }
  const _f = (d: BigNumber) => d.mul(borrowRate).div(10000)
  let d = deposit
  Array.from({ length: loop }).forEach(() => {
    d = _f(d)
  })
  return d
}

// Note: refactor this redundant code
const totalDepositExpected = (
  loop: number,
  deposit: BigNumber,
  borrowRate: BigNumber
) => {
  return [...Array(loop).keys()].reduce(
    (acc, cur) => acc.add(depositExpected(cur, deposit, borrowRate)),
    BigNumber.from('0')
  )
}

const totalBorrowExpected = (
  loop: number,
  deposit: BigNumber,
  borrowRate: BigNumber
) => {
  return totalDepositExpected(loop, deposit, borrowRate).sub(deposit)
}
