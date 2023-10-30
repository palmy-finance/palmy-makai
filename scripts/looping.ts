import {} from '@starlay-finance/contract-helpers'
import { ethers } from 'ethers'
import {
  getERC20ABI,
  getLeveragerABI,
  getLeveragerAddress,
} from './common/file'
import { gasLimit, getWallet, provider } from './common/wallet'

const network = process.env.NETWORK || 'ganache'

const adminWallet = getWallet(0)

const main = async () => {
  const contract = new ethers.Contract(
    getLeveragerAddress(network),
    getLeveragerABI(),
    adminWallet
  )
  const gasPrice = (await provider.getGasPrice()).mul(10)
  console.log('gasPrice: ', Number(gasPrice))

  /////////////////////////////////////////////
  // 1. Choose Asset
  /////////////////////////////////////////////

  // -------------- LTV: 8000 ----------------
  // USDC
  // const asset = '0x6a2d262D56735DbA19Dd70682B39F6bE9a931D98'
  // const tokenAmount = ethers.utils.parseUnits('100', 6)
  // const variableDebt = '0xd3270b3249Fa2F0ea85231311524229fF536ee0f'

  // USDT
	const asset = '0x3795C36e7D12A8c252A20C5a7B455f7c57b60283'
	const tokenAmount = ethers.utils.parseUnits('100', 6)
	const variableDebt = '0xfD001Ed8A6AefaA16a2A8673f9Ec5Ccbbb4ba38C'
	const lToken = '0x430D50963d9635bBef5a2fF27BD0bDDc26ed691F'

  // WETH
  // const asset = '0x81ECac0D6Be0550A00FF064a4f9dd2400585FE9c'
  // const tokenAmount = ethers.utils.parseUnits('0.00001', 18)
  // const variableDebt = '0x3D1e61a9c47b67FD990583d07Fe0c6C54AaFF42b'

  // BUSD
  // const asset = '0x4Bf769b05E832FCdc9053fFFBC78Ca889aCb5E1E'
  // const tokenAmount = ethers.utils.parseUnits('1', 18)
  // const variableDebt = '0xB3D6A83491E251bE0e9c21C8D84F88e15F6D9B15'
  // const lToken = '0xb7aB962c42A8Bb443e0362f58a5A43814c573FFb'

  // -------------- LTV: 7000 ----------------
  // WBTC
  // const asset = '0xad543f18cFf85c77E140E3E5E3c3392f6Ba9d5CA'
  // const tokenAmount = ethers.utils.parseUnits('0.1', 8)
  // const variableDebt = '0x8c2e483aCF644190123BC46719c6D611466F9835'

  // -------------- LTV: 4000 ----------------
  // ASTR
  // const asset = '0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720'
  // const tokenAmount = ethers.utils.parseUnits('0.1', 18)
  // const variableDebt = '0x5c00f026397379b70c6089C74E416b9797fdeab0'
  // const lToken = '0xc0043Ad81De6DB53a604e42377290EcfD4Bc5fED'

  // WSDN
  // const asset = '0x75364D4F779d0Bd0facD9a218c67f87dD9Aff3b4'
  // const tokenAmount = ethers.utils.parseUnits('0.1', 18)
  // const variableDebt = '0xd4Eabc34bD5F8837B378d6bf8f8A2F645200DC21'

  /////////////////////////////////////////////
  // 2. Looping
  /////////////////////////////////////////////

  // const token = new ethers.Contract(asset, getERC20ABI(), adminWallet)
  // const txApprove = await token.approve(contract.address, tokenAmount.mul(10), {
  //   gasLimit: gasLimit(),
  //   gasPrice: gasPrice,
  // })
  // await txApprove.wait()

  // const vdToken = new ethers.Contract(variableDebt, getERC20ABI(), adminWallet)

  // const txApprove2 = await vdToken.approveDelegation(
  //   contract.address,
  //   tokenAmount,
  //   {
  //     gasLimit: gasLimit(),
  //     gasPrice: gasPrice,
  //   }
  // )
  // await txApprove2.wait()
  // const txLoop = await contract
  //   .connect(adminWallet)
  //   .loop(asset, tokenAmount, 2, 1000, 20, {
  //     gasLimit: gasLimit(),
  //     gasPrice: gasPrice,
  //   })
  // await txLoop.wait()

  /////////////////////////////////////////////
  // 2. ASTR Looping
  /////////////////////////////////////////////

  // const token = new ethers.Contract(asset, getERC20ABI(), adminWallet)
  // const txApprove = await token.approve(contract.address, tokenAmount.mul(10), {
  //   gasLimit: gasLimit(),
  //   gasPrice: gasPrice,
  // })
  // await txApprove.wait()

  // const vdToken = new ethers.Contract(variableDebt, getERC20ABI(), adminWallet)

  // const txApprove2 = await vdToken.approveDelegation(
  //   contract.address,
  //   tokenAmount.mul(10),
  //   {
  //     gasLimit: gasLimit(),
  //     gasPrice: gasPrice,
  //   }
  // )
  // await txApprove2.wait()

  // const txLoop = await contract.connect(adminWallet).loopASTR(2, 1000, 20, {
  //   value: tokenAmount,
  //   gasLimit: gasLimit(),
  //   gasPrice: gasPrice,
  // })
  // await txLoop.wait()

  /////////////////////////////////////////////
  // 3. Reversed Looping
  /////////////////////////////////////////////

  console.log(1)
  const available = await contract
    .connect(adminWallet)
    .withdrawable(adminWallet.address, asset)
  console.log(Number(available.totalCollateral))
  console.log(Number(available.totalDebt))
  console.log(Number(available.currentLiquidationThreshold))
  console.log(Number(available.afford))
  console.log(Number(available.withdrawableCollateral))
  console.log(Number(available.withdrawAmount))

  const withdrawAmount = available.withdrawAmount
  const healthFactor = await contract
    .connect(adminWallet)
    .getHealthFactor(adminWallet.address, asset, withdrawAmount)
  console.log(Number(healthFactor))

  const ibToken = new ethers.Contract(lToken, getERC20ABI(), adminWallet)
  const txApproveLToken = await ibToken.approve(
    contract.address,
    tokenAmount.mul(100000),
    {
      gasLimit: gasLimit(),
      gasPrice: gasPrice,
    }
  )
  await txApproveLToken.wait()
  console.log(2)

  const txReverse = await contract.connect(adminWallet).close(asset, {
    gasLimit: gasLimit(),
    gasPrice: gasPrice,
  })
  await txReverse.wait()
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err)
    process.exit(1)
  })
