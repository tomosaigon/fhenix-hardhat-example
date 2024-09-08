import { WrappingERC20 } from "../types";
import { task } from "hardhat/config";
import type { TaskArguments } from "hardhat/types";

task("task:getName").setAction(async function (
  _taskArguments: TaskArguments,
  hre,
) {
  const { fhenixjs, ethers, deployments } = hre;
  const [signer] = await ethers.getSigners();

  const WrappingERC20 = await deployments.get("WrappingERC20");

  console.log(`Running getName, targeting contract at: ${WrappingERC20.address}`);

  const contract = (await ethers.getContractAt(
    "WrappingERC20",
    WrappingERC20.address,
  )) as unknown as unknown as WrappingERC20;

  // let permit = await fhenixjs.generatePermit(
  //   WrappingERC20.address,
  //   undefined, // use the internal provider
  //   signer,
  // );

  const result = await contract.name();
  console.log(`got : ${result.toString()}`);

  // const sealedResult = await contract.getCounterPermitSealed(permit);
  // let unsealed = fhenixjs.unseal(WrappingERC20.address, sealedResult);

  // console.log(`got unsealed result: ${unsealed.toString()}`);
});
