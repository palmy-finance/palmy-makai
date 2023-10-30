import fs from 'fs'
import path from 'path'

export const getLeveragerABI = () => {
  const compiled = JSON.parse(
    fs.readFileSync(getCompiledLeveragerPath()).toString()
  )
  return compiled.abi
}

export const getERC20ABI = () => {
  const compiled = JSON.parse(
    fs.readFileSync(getCompiledERC20Path()).toString()
  )
  return compiled.abi
}

export const getLeveragerAddress = (network: string) => {
  const json = JSON.parse(fs.readFileSync(getLeveragerPath(network)).toString())
  return json.address
}

export const getCompiledLeveragerPath = () =>
  path.join(
    __dirname,
    '..',
    '..',
    'build',
    'artifacts',
    'contracts',
    'Leverager.sol',
    'Leverager.json'
  )

export const getCompiledERC20Path = () =>
  path.join(
    __dirname,
    '..',
    '..',
    'build',
    'artifacts',
    'contracts',
    'Leverager.sol',
    'IERC20.json'
  )

export const getLeveragerPath = (network: string) =>
  path.join(__dirname, '..', '..', 'deployments', network, 'Leverager.json')
