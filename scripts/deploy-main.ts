import hre, { ethers } from "hardhat";

async function main() {
  console.log("Selected network: ", hre.network.name);
  // const contractName = "Erc721SoftStake";
  // const contract = await ethers.deployContract(contractName, [5,1]);
  const contractName = "Erc721SoftStake";
  const contract = await ethers.deployContract(contractName, [5,1]);
  console.log(await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
