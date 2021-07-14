const AMCToken = artifacts.require("AMCToken");
const AMCStaking = artifacts.require("AMCStaking");

const DEV_WALLET = "0xACd30ED0c0734a6F94412C08892A597A6134E45C";
const MANAGER_WALLET = "0xB340d045E4cF4a4DCb757b4A43aF6B865f9F7933";
const BNB_POOL_ADDRESS = "0xd0eeaa18e7b703cffd1e403294605028e5443b36";
const BNB_SPONSOR = "0xc96d00235f7601bb97647ed7aee0b982a7e3bd1a";
module.exports = async function (deployer) {
  await deployer.deploy(AMCToken, DEV_WALLET, MANAGER_WALLET, "40000000000000000000", BNB_POOL_ADDRESS, BNB_SPONSOR);
  const token = await AMCToken.deployed();
  await deployer.deploy(AMCStaking, token.address, "12000000000000000000")
  const staking = await AMCStaking.deployed();
  await token.setStaking(staking.address)
};