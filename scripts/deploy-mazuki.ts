import hre, { ethers } from "hardhat";

async function main() {
  console.log("Selected network: ", hre.network.name);
  const contractName = "MockAzuki";
  const contract = await ethers.deployContract(contractName);
  console.log(await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
