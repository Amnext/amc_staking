const AMCToken = artifacts.require("AMCToken");

const DEV_WALLET = "0x362C378e0855545C521b62bdEDeff54a8a4C677A";
const MANAGER_WALLET = "0xDF40cD1dA7045E855F7C0e351475F49f810a04a7";

module.exports = async function (deployer) {
  await deployer.deploy(AMCToken, DEV_WALLET, MANAGER_WALLET, "100000000000000000000");
  const token = AMCToken.deployed();
};