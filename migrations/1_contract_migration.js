const AMCToken = artifacts.require("AMCToken");
const AMCStaking = artifacts.require("AMCStaking");

const DEV_WALLET = "0x362C378e0855545C521b62bdEDeff54a8a4C677A";
const MANAGER_WALLET = "0xDF40cD1dA7045E855F7C0e351475F49f810a04a7";
const BNB_POOL_ADDRESS = "0xbccd4a3c8df54c887e5742fba5dc2a6f0c701f59";
const BNB_SPONSOR = "0xFd6a98cD1a84713A74F8Aa8869537b20dfFFd515";
module.exports = async function (deployer) {
  await deployer.deploy(AMCToken, DEV_WALLET, MANAGER_WALLET, "100000000000000000000", BNB_POOL_ADDRESS, BNB_SPONSOR);
  const token = AMCToken.deployed();
  await deployer.deploy(AMCStaking, token.address, "6000000000000000000")
  const staking = AMCStaking.deployed();
  await token.setStaking(staking.address)
};