import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers } from "hardhat";

export interface IHardhatTestCtx<T> {
  contract: T;
  accounts: Record<string, HardhatEthersSigner>;
}

export async function deployContract<T>(
  name: string,
  ...args: (string | number)[]
): Promise<IHardhatTestCtx<T>> {
  const Contract = await ethers.getContractFactory(name);
  const contract: any = await Contract.deploy(...args);
  // await contract.deployed();

  // console.log("estimateGas: ", contract.estimateGas);
  const [owner, user1, user2] = await ethers.getSigners();
  return {
    contract,
    accounts: {
      owner,
      user1,
      user2
    }
  };
}
