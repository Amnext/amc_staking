const AMCToken = artifacts.require("AMCToken");
const AMCStaking = artifacts.require("AMCStaking");

const DEV_WALLET = "0x8b878Ee3B32b0dFeA6142F5ca1EfebA8c5dFEc7e";
const MANAGER_WALLET = "0x8b878Ee3B32b0dFeA6142F5ca1EfebA8c5dFEc7e";
const BNB_POOL_ADDRESS = "0x2632a11973ae02aa6bc2ae5d37175339869c6534";
const BNB_SPONSOR = "0xe263cc642834c189fdb33ee6f2069d5462d4368c";

module.exports = async function (deployer) {
  await deployer.deploy(AMCToken, DEV_WALLET, MANAGER_WALLET, "100000000000000000000", BNB_POOL_ADDRESS, BNB_SPONSOR);
  const token = await AMCToken.deployed();
  await deployer.deploy(AMCStaking, token.address, "6000000000000000000")
  const staking = await AMCStaking.deployed();
  await token.setStaking(staking.address)
};