import { ethers } from 'hardhat'

export const parseToken = (amount: number) => {
  return ethers.utils.parseUnits(String(amount), 18)
}
