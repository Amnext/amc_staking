const AMCToken = artifacts.require("AMCToken");
const AMCStaking = artifacts.require("AMCStaking");

const DEV_WALLET = "0x22905BdFd65cEE48882c68a7761A89C9B8F0494D";
const MANAGER_WALLET = "0x6C44eDacc815Cd625ca7191fF74D30B9c72104a3";
const BNB_POOL_ADDRESS = "0xbccd4a3c8df54c887e5742fba5dc2a6f0c701f59";
const BNB_SPONSOR = "0xfd6a98cd1a84713a74f8aa8869537b20dfffd515";
module.exports = async function (deployer) {
  await deployer.deploy(AMCToken, DEV_WALLET, MANAGER_WALLET, "40000000000000000000", BNB_POOL_ADDRESS, BNB_SPONSOR);
  const token = await AMCToken.deployed();
  await deployer.deploy(AMCStaking, token.address, "12000000000000000000")
  const staking = await AMCStaking.deployed();
  await token.setStaking(staking.address)
};