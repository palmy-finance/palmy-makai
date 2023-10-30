import { ethers, waffle } from 'hardhat'

describe('leverager', () => {
  const [user1, user2, user3, user4] = waffle.provider.getWallets()

  it('should be', async () => {
    const Leverager = await ethers.getContractFactory('Leverager')
    const leverager = await Leverager.deploy(
      '0x90384334333f3356eFDD5b20016350843b90f182',
      '0x90384334333f3356eFDD5b20016350843b90f182',
      '0x90384334333f3356eFDD5b20016350843b90f182'
    )
  })
})
