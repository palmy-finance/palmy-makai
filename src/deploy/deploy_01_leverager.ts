import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()
  const { deploy } = deployments

  // shiden
  // const lendingPool = '0xF51Ff87C3B673DF459Ba2F52dB223DC317cD8537'

  // astar
  const lendingPool = '0x90384334333f3356eFDD5b20016350843b90f182'
  const wastr = '0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720'

  await deploy('Leverager', {
    from: deployer,
    args: [lendingPool, wastr],
    log: true,
    deterministicDeployment: false,
  })
}

export default deploy
