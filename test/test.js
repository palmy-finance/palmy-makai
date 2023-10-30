const { expect } = require("chai");
const { ethers } = require("hardhat");
import { parseToken } from "../utils/number";

describe("makai", function () {
  let asset;
  let lasset;
  let ltoken;
  let wastar;
  let erc20;
  let user;
  let dominator;
  let lendingpool;
  let LP;
  let leverager;
  let LV;
  let oracle;

  beforeEach(async function () {
    [dominator, user, ltoken] = await ethers.getSigners();
    erc20 = await ethers.getContractFactory("contracts/mocks/ERC20.sol:ERC20");
    asset = await erc20.deploy(
      "USDC",
      "USDC",
      user.address,
      parseToken("1000")
    );
    wastar = await erc20.deploy(
      "WASTR",
      "WASTR",
      dominator.address,
      parseToken(100)
    );

    ltoken = await ethers.getContractFactory(
      "contracts/mocks/LToken.sol:LToken"
    );
    lasset = await ltoken.deploy("lUSDC", "lUSDC");

    lendingpool = await ethers.getContractFactory(
      "contracts/mocks/LendingPool.sol:LendingPool"
    )
    oracle = await (await ethers.getContractFactory(
      "contracts/mocks/PriceOracle.sol:PriceOracle"
    )).deploy();
    LP = await lendingpool
      .connect(dominator)
      .deploy(asset.address, lasset.address);
    await LP.deployed();

    leverager = await ethers.getContractFactory(
      "contracts/Leverager.sol:Leverager"
    );
    LV = await leverager.connect(dominator).deploy(LP.address, wastar.address, oracle.address);
    await LV.deployed();
  });

  it("loop", async function () {
    console.log("ltv is %s", await LV.ltv(asset.address));
    await asset.connect(user).approve(LV.address, parseToken("1000"));

    await LV.connect(user).loop(asset.address, parseToken("100"), 2, 8000, 10);
    console.log("totalDposit is %s", await LP.totalDeposit(asset.address));
    console.log("totalBorrow is %s", await LP.totalBorrow(asset.address));

  });
});
