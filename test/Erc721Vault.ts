import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "./helper";
import { Erc721Vault } from "../typechain-types/contracts";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import {
  Mock721,
  NormalContract,
  Mock20
} from "../typechain-types/contracts/example";

const CONTRACT_NAME = "Erc721Vault";
type ContractType = Erc721Vault;

interface IMintAndStakeReturned {
  tokenId: bigint;
  timestamp: number;
}

describe(CONTRACT_NAME, function () {
  const stakingInterval = 5;
  let contract: ContractType;
  let contractAddr: string;
  let contractOwnerCalls: ContractType;
  let contractUser1Calls: ContractType;
  let contractUser2Calls: ContractType;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let nftContract1: Mock721;
  let nftContract2: Mock721;
  let nftContractAddr1: string;
  let nftContractAddr2: string;

  let nonNftContract: Mock20;
  let normalContract: NormalContract;
  const notAOwnerErrMsg = "Ownable: caller is not the owner";
  before(async () => {
    nonNftContract = (await deployContract<Mock20>("Mock20")).contract;
    normalContract = (await deployContract<NormalContract>("NormalContract"))
      .contract;
  });
  beforeEach(async () => {
    const ctx = await deployContract<ContractType>(
      CONTRACT_NAME,
      stakingInterval
    );
    contract = ctx.contract;
    contractAddr = await contract.getAddress();
    nftContract1 = (await deployContract<Mock721>("Mock721")).contract;
    nftContract2 = (await deployContract<Mock721>("Mock721")).contract;
    nftContractAddr1 = await nftContract1.getAddress();
    nftContractAddr2 = await nftContract2.getAddress();
    owner = ctx.accounts.owner;
    user1 = ctx.accounts.user1;
    user2 = ctx.accounts.user2;
    contractOwnerCalls = contract.connect(owner);
    contractUser1Calls = contract.connect(user1);
    contractUser2Calls = contract.connect(user2);
  });
  // const getTimestampNowInSec = () => Math.floor(Date.now() / 1000);
  const mintAndApprove = async (
    caller: HardhatEthersSigner,
    nftContract: Mock721,
    tokenId?: number
  ): Promise<bigint> => {
    let tokenIdOut: bigint;
    if (tokenId) {
      await nftContract.connect(caller).mintWithTokenId(tokenId);
      tokenIdOut = BigInt(tokenId);
    } else {
      await nftContract.connect(caller).mint();
      tokenIdOut = (await nftContract.totalSupply()) - 1n;
    }
    await nftContract.connect(caller).approve(contractAddr, tokenIdOut);
    return tokenIdOut;
  };
  const mintAndStake = async (
    caller: HardhatEthersSigner,
    nftContract: Mock721,
    tokenId?: number
  ): Promise<IMintAndStakeReturned> => {
    const id = await mintAndApprove(caller, nftContract, tokenId);
    await contract.connect(caller).stake(nftContract.getAddress(), id);
    return {
      tokenId: id,
      timestamp: await time.latest()
    };
  };
  const calculatedScore = async (
    stake: IMintAndStakeReturned,
    weight: number
  ): Promise<number> => {
    const blockTime = await time.latest();
    return Math.floor((blockTime - stake.timestamp) / stakingInterval) * weight;
  };
  const calculatedStakeScores = async (
    stakes: IMintAndStakeReturned[],
    weights: number[]
  ): Promise<number> => {
    return stakes.reduce<Promise<number>>(async (prev, stake, i) => {
      const score = await calculatedScore(stake, weights[i]);
      return (await prev) + score;
    }, Promise.resolve(0));
  };
  describe("toggleStakingAllowed", () => {
    describe("when caller is not the owner", async () => {
      it("should revert", async () => {
        await expect(contractUser1Calls.toggleStakingAllowed()).revertedWith(
          notAOwnerErrMsg
        );
      });
    });
    describe("when caller is owner", () => {
      it("should toggle and emit a event when it's opened", async () => {
        expect(await contract.isStakingAllowed()).eq(false);
        await expect(contractOwnerCalls.toggleStakingAllowed()).emit(
          contract,
          "StakingOpen"
        );
      });
      it("should toggle and emit a event when it's closed", async () => {
        expect(await contract.isStakingAllowed()).eq(false);
        await contractOwnerCalls.toggleStakingAllowed();
        await expect(contractOwnerCalls.toggleStakingAllowed()).emit(
          contract,
          "StakingClose"
        );
      });
    });
  });
  describe("setStakeInterval", () => {
    const interval = 20;
    describe("when caller is not the owner", async () => {
      it("should revert", async () => {
        await expect(
          contractUser1Calls.setStakeInterval(interval)
        ).revertedWith(notAOwnerErrMsg);
      });
    });
    describe("when caller is owner", () => {
      it("should set stakeInterval and emit a event", async () => {
        await expect(contractOwnerCalls.setStakeInterval(interval))
          .emit(contract, "SetStakeInterval")
          .withArgs(interval);
        expect(await contract.stakingInterval());
      });
    });
  });
  describe("whitelistedColQuota", () => {
    describe("setWhitelistedCol", () => {
      describe("when caller is not the owner", async () => {
        it("should revert", async () => {
          await expect(
            contractUser1Calls.setWhitelistedCol(nftContractAddr1, 0, 1)
          ).revertedWith(notAOwnerErrMsg);
        });
      });
      describe("when caller is owner", () => {
        it("should throw if quota is less than or 0", async () => {
          await expect(
            contractOwnerCalls.setWhitelistedCol(nftContractAddr1, 0, 1)
          ).revertedWith("quota and weight should be non-zero value");
        });
        it("should throw if weight is less than or 0", async () => {
          await expect(
            contractOwnerCalls.setWhitelistedCol(nftContractAddr1, 1, 0)
          ).revertedWith("quota and weight should be non-zero value");
        });
        it("should add the data and emit event if it does not exists", async () => {
          const quota = 12;
          expect(await contract.getAllWhitelistedCol()).deep.eq([[], [], []]);
          await expect(
            contractOwnerCalls.setWhitelistedCol(nftContractAddr1, quota, 1)
          )
            .emit(contract, "SetWhitelistedCollection")
            .withArgs(nftContractAddr1, quota, 1);
          expect(await contract.getAllWhitelistedCol()).deep.eq([
            [nftContractAddr1],
            [quota],
            [1]
          ]);
        });
        it("should modify the data and emit event if it exists", async () => {
          const quota = 12;
          await contract.setWhitelistedCol(nftContractAddr1, quota, 1);
          await expect(
            contractOwnerCalls.setWhitelistedCol(
              nftContractAddr1,
              quota + 34,
              3
            )
          )
            .emit(contract, "SetWhitelistedCollection")
            .withArgs(nftContractAddr1, quota + 34, 3);
          expect(await contract.getAllWhitelistedCol()).deep.eq([
            [nftContractAddr1],
            [quota + 34],
            [3]
          ]);
        });
      });
    });
    describe("delWhitelistedCol", () => {
      describe("when caller is not the owner", async () => {
        it("should revert", async () => {
          await expect(
            contractUser1Calls.delWhitelistedCol(nftContractAddr1)
          ).revertedWith(notAOwnerErrMsg);
        });
      });
      describe("when caller is owner", () => {
        it("should throw if the addr does not exist", async () => {
          await expect(
            contractOwnerCalls.delWhitelistedCol(nftContractAddr1)
          ).revertedWith("not exist");
        });
        it("should remove the data and emit event if the addr exists", async () => {
          await contractOwnerCalls.setWhitelistedCol(nftContractAddr1, 12, 6);
          await contractOwnerCalls.setWhitelistedCol(nftContractAddr2, 13, 9);
          await expect(contractOwnerCalls.delWhitelistedCol(nftContractAddr1))
            .emit(contract, "DeleteWhitelistedCollection")
            .withArgs(nftContractAddr1);
          expect(await contract.getAllWhitelistedCol()).deep.eq([
            [nftContractAddr2],
            [13],
            [9]
          ]);
        });
      });
    });
  });
  describe("stake", () => {
    describe("pre-checks", () => {
      it("should revert when staking is closed", async () => {
        expect(await contract.isStakingAllowed()).eq(false);
        await expect(contractUser1Calls.stake(user1.address, 0)).revertedWith(
          "staking is closed"
        );
      });
      describe("when contract checking fails", () => {
        beforeEach(async () => {
          await contractOwnerCalls.toggleStakingAllowed();
          expect(await contract.isStakingAllowed()).eq(true);
        });
        const expectedErrorMsg = "not a valid erc-721 address";
        it("should throw if it's user account address", async () => {
          await expect(contractUser1Calls.stake(user1.address, 0)).revertedWith(
            expectedErrorMsg
          );
        });
        it("should throw if contract does not support ERC-165", async () => {
          await expect(
            contractUser1Calls.stake(normalContract.getAddress(), 0)
          ).revertedWith(expectedErrorMsg);
        });
        it("should throw if contract support ERC-165 but it's not ERC-721", async () => {
          await expect(
            contractUser1Calls.stake(nonNftContract.getAddress(), 0)
          ).revertedWith(expectedErrorMsg);
        });
      });
      it("should revert when collection is not whitelisted", async () => {
        await contractOwnerCalls.toggleStakingAllowed();
        expect(await contract.isStakingAllowed()).eq(true);
        await expect(
          contractUser1Calls.stake(nftContractAddr1, 0)
        ).revertedWith("not whitelisted");
      });
      it("should revert when collection is whitelisted but no more quota", async () => {
        await contractOwnerCalls.toggleStakingAllowed();
        await contract.setWhitelistedCol(nftContractAddr1, 1, 1);
        expect(await contract.isStakingAllowed()).eq(true);
        // Mint and approve 2 Nft from nftContract1 for user1
        const id1 = await mintAndApprove(user1, nftContract1);
        const id2 = await mintAndApprove(user1, nftContract1);
        // Stake 1 Nft into vault
        await contractUser1Calls.stake(nftContractAddr1, id1);
        await expect(
          contractUser1Calls.stake(nftContractAddr1, id2)
        ).revertedWith("reach max quota of collection");
      });
      it("should revert when caller is not the owner of NFT", async () => {
        await contractOwnerCalls.toggleStakingAllowed();
        await contract.setWhitelistedCol(nftContractAddr1, 1, 2);
        await mintAndApprove(user2, nftContract1);
        await expect(
          contractUser1Calls.stake(nftContractAddr1, 0)
        ).revertedWith("ERC721: transfer from incorrect owner");
      });
    });
    describe("passed pre-checks", () => {
      beforeEach(async () => {
        await contractOwnerCalls.toggleStakingAllowed();
        await contract.setWhitelistedCol(nftContractAddr1, 100, 5);
        await contract.setWhitelistedCol(nftContractAddr2, 100, 1);
        expect(await contract.isStakingAllowed()).eq(true);
      });
      it("should transfer the Nft to the vault", async () => {
        // Mint 1 and approve Nft from nftContract1 for user1
        const id1 = await mintAndApprove(user1, nftContract1);
        const id2 = await mintAndApprove(user1, nftContract1, 17);
        const id3 = await mintAndApprove(user1, nftContract2);
        await expect(contract.connect(user1).stake(nftContractAddr1, id1))
          .emit(contract, "NFTStaked")
          .withArgs(user1.address, nftContractAddr1, id1);
        await expect(contract.connect(user1).stake(nftContractAddr1, id2))
          .emit(contract, "NFTStaked")
          .withArgs(user1.address, nftContractAddr1, id2);
        await expect(contract.connect(user1).stake(nftContractAddr2, id3))
          .emit(contract, "NFTStaked")
          .withArgs(user1.address, nftContractAddr2, id3);
      });
    });
  });
  describe("unstake", () => {
    const weights = [5, 1];
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, weights[0]);
      await contract.setWhitelistedCol(nftContractAddr2, 100, weights[1]);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    describe("pre-checks", () => {
      it("should revert if the item is not staked", async () => {
        await expect(
          contractUser1Calls.unstake(nftContractAddr1, 0)
        ).revertedWith("item not exists");
      });
      it("should revert if the item is staked but caller not the staker", async () => {
        await mintAndStake(user2, nftContract1, 0);
        await expect(
          contractUser1Calls.unstake(nftContractAddr1, 0)
        ).revertedWith("item not exists");
      });
    });
    describe("passed pre-checks", () => {
      it("should transfer item to sender and remove record data", async () => {
        const stake1 = await mintAndStake(user1, nftContract1);
        expect(await nftContract1.ownerOf(stake1.tokenId)).eq(contractAddr);
        expect(await contract.userStakedItems(user1.address)).length(1);
        await time.increase(3721);
        await expect(
          contractUser1Calls.unstake(nftContractAddr1, stake1.tokenId)
        )
          .emit(contract, "NFTUnstaked")
          .withArgs(user1.address, nftContractAddr1, stake1.tokenId);
        const expectedScore = await calculatedScore(stake1, weights[0]);
        expect(await nftContract1.ownerOf(stake1.tokenId)).eq(user1.address);
        expect(await contract.userStakedItems(user1.address)).length(0);
        expect((await contract.userScore(user1.address))[1]).eq(expectedScore);
      });
    });
  });
  describe("userStakedItems", () => {
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, 5);
      await contract.setWhitelistedCol(nftContractAddr2, 100, 1);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    it("should print staked item from an address", async () => {
      const { tokenId, timestamp } = await mintAndStake(user1, nftContract1);
      const actual = await contract.userStakedItems(user1.address);
      expect(actual).length(1);
      expect(actual[0]).deep.eq([nftContractAddr1, tokenId, timestamp]);
    });
    it("multiple stakes in single contract", async () => {
      const stake1 = await mintAndStake(user1, nftContract1);
      const stake2 = await mintAndStake(user1, nftContract1, 123);
      const actual = await contract.userStakedItems(user1.address);
      expect(actual).length(2);
      expect(actual[0]).deep.eq([
        nftContractAddr1,
        stake1.tokenId,
        stake1.timestamp
      ]);
      expect(actual[1]).deep.eq([
        nftContractAddr1,
        stake2.tokenId,
        stake2.timestamp
      ]);
    });
    it("multiple stakes in multiple contracts", async () => {
      const stake1 = await mintAndStake(user1, nftContract1);
      const stake2 = await mintAndStake(user2, nftContract1, 57);
      const stake3 = await mintAndStake(user1, nftContract2);
      const stake4 = await mintAndStake(user1, nftContract1, 123);
      const stake5 = await mintAndStake(user2, nftContract2, 617);
      const actual1 = await contract.userStakedItems(user1.address);
      const actual2 = await contract.userStakedItems(user2.address);
      expect(actual1).length(3);
      expect(actual2).length(2);
      expect(actual1).deep.eq([
        [nftContractAddr1, stake1.tokenId, stake1.timestamp],
        [nftContractAddr1, stake4.tokenId, stake4.timestamp],
        [nftContractAddr2, stake3.tokenId, stake3.timestamp]
      ]);
      expect(actual2).deep.eq([
        [nftContractAddr1, stake2.tokenId, stake2.timestamp],
        [nftContractAddr2, stake5.tokenId, stake5.timestamp]
      ]);
    });
  });
  describe("itemStakingStat", () => {
    const weight = 39;
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, weight);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    describe("item not exist", async () => {
      it("should revert", async () => {
        await expect(
          contract.itemStakingStat(user1.address, nftContractAddr1, 0)
        ).revertedWith("item not exists");
      });
    });
    it("should return 0 if col is not whitelisted", async () => {
      const { tokenId } = await mintAndStake(user1, nftContract1);
      await contract.delWhitelistedCol(nftContractAddr1);
      const actual = await contract.itemStakingStat(
        user1.address,
        nftContractAddr1,
        tokenId
      );
      expect(actual[1]).eq(0);
    });
    it("should print valid score", async () => {
      const diff = 250;
      const { tokenId, timestamp } = await mintAndStake(user1, nftContract1);
      await time.increase(diff);
      await mintAndStake(user1, nftContract1);
      const expected =
        Math.floor(((await time.latest()) - timestamp) / stakingInterval) *
        weight;
      const actual = await contract.itemStakingStat(
        user1,
        nftContractAddr1,
        tokenId
      );
      expect(actual[1]).eq(expected);
    });
  });
  describe("userScore", () => {
    const weights = [39, 9];
    const intervals = [123, 456, 789];
    const mintAndStakeForWhile = async (): Promise<
      (IMintAndStakeReturned & {
        weight: number;
      })[]
    > => {
      const stakes: (IMintAndStakeReturned & { weight: number })[] = [];
      expect(await contract.isStakingAllowed()).eq(true);
      stakes.push({
        ...(await mintAndStake(user1, nftContract1)),
        weight: weights[0]
      });
      await time.increase(intervals[0]);
      stakes.push({
        ...(await mintAndStake(user1, nftContract2)),
        weight: weights[1]
      });
      await time.increase(intervals[1]);
      stakes.push({
        ...(await mintAndStake(user1, nftContract1, 123)),
        weight: weights[0]
      });
      await time.increase(intervals[2]);
      return stakes;
    };
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, weights[0]);
      await contract.setWhitelistedCol(nftContractAddr2, 100, weights[1]);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    it("should return valid score when user has no hist score", async () => {
      const stakes = await mintAndStakeForWhile();
      const actual = await contract.userScore(user1);
      const expectedScore = await calculatedStakeScores(stakes, [
        weights[0],
        weights[1],
        weights[0]
      ]);
      expect(actual[1]).eq(expectedScore);
    });
    it("should return valid score when user has hist score", async () => {
      const stake1 = await mintAndStake(user1, nftContract1);
      await time.increase(3721);
      await contractUser1Calls.unstake(nftContractAddr1, stake1.tokenId);
      const histScore = await calculatedScore(stake1, weights[0]);
      expect((await contract.userScore(user1.address))[1]).eq(histScore);

      const stakes = await mintAndStakeForWhile();
      const actual = await contract.userScore(user1);
      const expectedScore = await calculatedStakeScores(stakes, [
        weights[0],
        weights[1],
        weights[0]
      ]);
      expect(actual[1]).eq(expectedScore + histScore);
    });
  });
  describe("rescue", () => {
    const weights = [5, 9];
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, weights[0]);
      await contract.setWhitelistedCol(nftContractAddr2, 100, weights[1]);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    it("should revert when caller is not the owner", async () => {
      await expect(contractUser1Calls.toggleStakingAllowed()).revertedWith(
        notAOwnerErrMsg
      );
    });
    it("should force to unstake item and transfer back the staker", async () => {
      const stake1 = await mintAndStake(user1, nftContract1);
      const stake2 = await mintAndStake(user1, nftContract2);
      const stake3 = await mintAndStake(user1, nftContract1);
      await mintAndStake(user2, nftContract2);
      expect(await nftContract1.ownerOf(stake3.tokenId)).eq(contractAddr);
      expect(await contract.userStakedItems(user1.address)).length(3);
      await time.increase(3721);
      await contractOwnerCalls.rescue(
        user1.address,
        nftContractAddr1,
        stake3.tokenId
      );
      const expectedScore = await calculatedStakeScores(
        [stake1, stake2, stake3],
        [5, 9, 5]
      );
      expect(await nftContract1.ownerOf(stake3.tokenId)).eq(user1.address);
      expect(await contract.userStakedItems(user1.address)).length(2);
      expect((await contract.userScore(user1.address))[1]).eq(expectedScore);
    });
  });
  describe("intergration test", () => {
    const weights = [51, 39];
    const random = (from: number, to: number) =>
      Math.floor((to - from) * Math.random()) + from;
    const waitForRandomTime = async () => time.increase(random(100, 10000));
    beforeEach(async () => {
      await contractOwnerCalls.toggleStakingAllowed();
      await contract.setWhitelistedCol(nftContractAddr1, 100, weights[0]);
      await contract.setWhitelistedCol(nftContractAddr2, 100, weights[1]);
      expect(await contract.isStakingAllowed()).eq(true);
    });
    it("single user stake and unstake", async () => {
      let histScore = 0;
      const stake1 = await mintAndStake(user1, nftContract1);
      await waitForRandomTime();
      await contractUser1Calls.unstake(nftContractAddr1, stake1.tokenId);
      histScore += await calculatedScore(stake1, weights[0]);
      const score1 = (await contract.userScore(user1))[1];
      expect(score1).eq(histScore);
      await nftContract1.connect(user1).approve(contractAddr, stake1.tokenId);
      await contractUser1Calls.stake(nftContractAddr1, stake1.tokenId);
      const stake2: IMintAndStakeReturned = {
        tokenId: stake1.tokenId,
        timestamp: await time.latest()
      };
      await waitForRandomTime();
      const stake3 = await mintAndStake(user1, nftContract1);
      await waitForRandomTime();
      const stake4 = await mintAndStake(user1, nftContract2);
      const stake5 = await mintAndStake(user1, nftContract1);
      await waitForRandomTime();
      expect(await contract.userStakedItems(user1.address)).length(4);
      await contractUser1Calls.unstake(nftContractAddr1, stake3.tokenId);
      histScore += await calculatedScore(stake3, weights[0]);
      await contractUser1Calls.unstake(nftContractAddr1, stake5.tokenId);
      histScore += await calculatedScore(stake5, weights[0]);
      await contractUser1Calls.unstake(nftContractAddr2, stake4.tokenId);
      histScore += await calculatedScore(stake4, weights[1]);
      await contractUser1Calls.unstake(nftContractAddr1, stake2.tokenId);
      histScore += await calculatedScore(stake2, weights[0]);
      expect((await contract.userScore(user1.address))[1]).eq(histScore);
    });
  });
});
