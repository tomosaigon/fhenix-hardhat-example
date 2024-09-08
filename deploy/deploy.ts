import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import chalk from "chalk";

const hre = require("hardhat");

const func: DeployFunction = async function () {
  const { fhenixjs, ethers } = hre;
  const { deploy } = hre.deployments;
  const [signer] = await ethers.getSigners();

  if ((await ethers.provider.getBalance(signer.address)).toString() === "0") {
    if (hre.network.name === "localfhenix") {
      await fhenixjs.getFunds(signer.address);
    } else {
        console.log(
            chalk.red("Please fund your account with testnet FHE from https://faucet.fhenix.zone"));
        return;
    }
  }

  const counter = await deploy("Counter", {
    from: signer.address,
    args: [],
    log: true,
    skipIfAlreadyDeployed: false,
  });
  console.log(`Counter contract: `, counter.address);

  const WrappingERC20 = await deploy("WrappingERC20", {
    from: signer.address,
    args: ["Test Token", "TST"],
    log: true,
    skipIfAlreadyDeployed: false
  });
  console.log(`WrappingERC20 contract: `, WrappingERC20.address);

  // const Vault = await deploy("Vault", {
  //   from: signer.address,
  //   args: [],
  //   log: true,
  //   skipIfAlreadyDeployed: false
  // });
  // console.log(`Vault contract: `, Vault.address);  

  const VickreyAuction = await deploy("VickreyAuction", {
    from: signer.address,
    args: [],
    log: true,
    skipIfAlreadyDeployed: false
  });
  console.log(`VickreyAuction contract: `, VickreyAuction.address);  

};

export default func;
func.id = "deploy_counter";
func.tags = ["Counter"];
