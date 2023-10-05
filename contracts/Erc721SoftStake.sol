//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// import "@openzeppelin/contracts/access/AccessControl.sol";

struct CollectionConfig {
  uint32 maxQuota;
  uint8 weight;
}
struct WhitelistedCollection {
  EnumerableSet.AddressSet colAddrSet;
  mapping(address => CollectionConfig) colMap;
  mapping(address => uint16) stakingQuotaMap;
}

struct UserStakingData {
  mapping(address => uint256) staked;
  EnumerableSet.AddressSet addrSet;
  mapping(address => EnumerableSet.AddressSet) addrToColIndexing;
  mapping(address => mapping(address => EnumerableSet.UintSet)) colToTokenIdIndexing;
  mapping(address => mapping(address => mapping(uint256 => uint256))) timestampMap;
}

struct UserStakedItem {
  address collection;
  uint256 tokenId;
  uint256 startAt;
}

struct ItemStakingStat {
  uint256 elapsed;
  uint256 score;
}

struct UserScore {
  uint256 timestamp;
  uint256 score;
}

contract Erc721SoftStake is Ownable, ReentrancyGuard, ERC721Holder {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableSet for EnumerableSet.AddressSet;
  bytes4 public erc721InterfaceId = 0x80ac58cd;
  uint16 public maxStakedDay;
  bool public isStakingAllowed;
  uint32 public stakingInterval;
  uint256 public holding;
  WhitelistedCollection internal wlCol;
  UserStakingData internal userStakingData;
  mapping(address => uint256) internal userHistScore;

  event StakingOpen();
  event StakingClose();
  event SetStakeInterval(uint32 interval);
  event SetMaxStakedDay(uint16 day);
  event SetWhitelistedCollection(
    address collection,
    uint16 quota,
    uint8 weight
  );
  event DeleteWhitelistedCollection(address collection);
  event VaultRecievedNft();
  event NFTStaked(address staker, address collection, uint256 tokenId);
  event NFTCheckIn(address staker, address collection, uint256 tokenId);
  event NFTUnstaked(address staker, address collection, uint256 tokenId);

  constructor(uint32 stakingInterval_) {
    isStakingAllowed = false;
    stakingInterval = stakingInterval_;
  }

  modifier stakingOpened() {
    require(isStakingAllowed, "staking is closed");
    _;
  }

  function toggleStakingAllowed() external onlyOwner {
    isStakingAllowed = !isStakingAllowed;
    if (isStakingAllowed) {
      emit StakingOpen();
    } else {
      emit StakingClose();
    }
  }

  function setMaxStakedDay(uint16 newValue) external onlyOwner {
    maxStakedDay = newValue;
    emit SetMaxStakedDay(newValue);
  }

  function setStakeInterval(uint32 newValue) external onlyOwner {
    stakingInterval = newValue;
    emit SetStakeInterval(newValue);
  }

  // O(1)
  function setWhitelistedCol(
    address collection,
    uint16 quota,
    uint8 weight
  ) external onlyOwner {
    require(
      quota > 0 && weight > 0,
      "quota and weight should be non-zero value"
    );
    wlCol.colMap[collection] = CollectionConfig(quota, weight);
    EnumerableSet.add(wlCol.colAddrSet, collection);
    emit SetWhitelistedCollection(collection, quota, weight);
  }

  // O(1)
  function delWhitelistedCol(address collection) external onlyOwner {
    require(EnumerableSet.contains(wlCol.colAddrSet, collection), "not exist");
    EnumerableSet.remove(wlCol.colAddrSet, collection);
    delete wlCol.colMap[collection];
    emit DeleteWhitelistedCollection(collection);
  }

  function getAllWhitelistedCol()
    external
    view
    returns (address[] memory, uint32[] memory, uint8[] memory)
  {
    uint256 size = EnumerableSet.length(wlCol.colAddrSet);
    address[] memory addrOut = new address[](size);
    uint32[] memory quotaOut = new uint32[](size);
    uint8[] memory weightOut = new uint8[](size);
    for (uint256 i = 0; i < size; i++) {
      address addr = EnumerableSet.at(wlCol.colAddrSet, i);
      addrOut[i] = addr;
      quotaOut[i] = wlCol.colMap[addr].maxQuota;
      weightOut[i] = wlCol.colMap[addr].weight;
    }
    return (addrOut, quotaOut, weightOut);
  }

  function _isValidErc721Contract(address col_) internal view returns (bool) {
    if (!Address.isContract(col_)) {
      return false;
    }
    try ERC721(col_).supportsInterface(erc721InterfaceId) returns (bool _v) {
      return _v;
    } catch (bytes memory) {
      return false;
    }
  }

  function _getItemStakingScore(
    address addr_,
    address col_,
    uint256 tokenId_
  ) internal view returns (uint256) {
    uint256 itemTimestamp = userStakingData.timestampMap[addr_][col_][tokenId_];
    return itemTimestamp;
  }

  function _getUserStakedItems(
    address addr_
  ) internal view returns (UserStakedItem[] memory) {
    uint256 userStaked = userStakingData.staked[addr_];
    uint256 pointer = 0;
    UserStakedItem[] memory items = new UserStakedItem[](userStaked);
    EnumerableSet.AddressSet storage colSet = userStakingData.addrToColIndexing[
      addr_
    ];
    uint256 colSetLength = EnumerableSet.length(colSet);
    for (uint256 i = 0; i < colSetLength; i++) {
      address col = EnumerableSet.at(colSet, i);
      EnumerableSet.UintSet storage tokenIdSet = userStakingData
        .colToTokenIdIndexing[addr_][col];
      uint256 tokenIdSetLength = EnumerableSet.length(tokenIdSet);
      for (uint256 j = 0; j < tokenIdSetLength; j++) {
        uint256 tokenId = EnumerableSet.at(tokenIdSet, j);
        uint256 timestamp = userStakingData.timestampMap[addr_][col][tokenId];
        items[pointer++] = UserStakedItem(col, tokenId, timestamp);
      }
    }
    return items;
  }

  function _postStakeAppendData(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    EnumerableSet.add(userStakingData.addrSet, staker_);
    EnumerableSet.add(userStakingData.addrToColIndexing[staker_], col_);
    EnumerableSet.add(
      userStakingData.colToTokenIdIndexing[staker_][col_],
      tokenId_
    );
    userStakingData.timestampMap[staker_][col_][tokenId_] = block.timestamp;
    wlCol.stakingQuotaMap[col_] += 1;
    holding += 1;
    userStakingData.staked[staker_] += 1;
  }

  function _removeStakedData(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    delete userStakingData.timestampMap[staker_][col_][tokenId_];
    EnumerableSet.remove(
      userStakingData.colToTokenIdIndexing[staker_][col_],
      tokenId_
    );
    if (
      EnumerableSet.length(
        userStakingData.colToTokenIdIndexing[staker_][col_]
      ) < 1
    ) {
      EnumerableSet.remove(userStakingData.addrToColIndexing[staker_], col_);
    }
    if (EnumerableSet.length(userStakingData.addrToColIndexing[staker_]) < 1) {
      delete userStakingData.addrToColIndexing[staker_];
      EnumerableSet.remove(userStakingData.addrSet, staker_);
    }
    wlCol.stakingQuotaMap[col_] -= 1;
    holding -= 1;
    userStakingData.staked[staker_] -= 1;
  }

  function users() external view returns (address[] memory) {
    uint256 len = EnumerableSet.length(userStakingData.addrSet);
    address[] memory out = new address[](len);
    for (uint256 i = 0; i < len; i++) {
      out[i] = EnumerableSet.at(userStakingData.addrSet, i);
    }
    return out;
  }

  function userStakedItems(
    address user
  ) public view returns (UserStakedItem[] memory) {
    return _getUserStakedItems(user);
  }

  function _isOwner(
    address addr_,
    address col_,
    uint256 id_
  ) internal view returns (bool) {
    address owner = ERC721(col_).ownerOf(id_);
    return owner == addr_;
  }

  function stake(
    address collection,
    uint256 tokenId
  ) external nonReentrant stakingOpened {
    require(_isValidErc721Contract(collection), "not a valid erc-721 address");
    uint32 maxQuota = wlCol.colMap[collection].maxQuota;
    require(maxQuota > 0, "not whitelisted");
    require(
      wlCol.stakingQuotaMap[collection] + 1 <= maxQuota,
      "reach max quota of collection"
    );
    require(_isOwner(msg.sender, collection, tokenId), "not a owner");
    // TODO: Check if staked but diff owner before and proceed
    // ERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
    _postStakeAppendData(msg.sender, collection, tokenId);
    emit NFTStaked(msg.sender, collection, tokenId);
  }
  function _getMaxScoreInSession() internal view returns(uint256) {

  }
  function singleCheckIn(
    address col_,
    uint256 tokenId_
  ) external nonReentrant stakingOpened {
    uint256 itemTimestamp = userStakingData.timestampMap[msg.sender][col_][
      tokenId_
    ];
    require(itemTimestamp > 0, "item not exists");

    // require(_isValidErc721Contract(collection), "not a valid erc-721 address");
    // uint32 maxQuota = wlCol.colMap[collection].maxQuota;
    // require(maxQuota > 0, "not whitelisted");
    // require(
    //   wlCol.stakingQuotaMap[collection] + 1 <= maxQuota,
    //   "reach max quota of collection"
    // );
    // require(_isOwner(msg.sender, collection, tokenId), "not a owner");
    // Check if staked but diff owner before and proceed
    // ERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
    // _postStakeAppendData(msg.sender, collection, tokenId);
    emit NFTCheckIn(msg.sender, col_, tokenId_);
  }

  function _unstakeSafe(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    // 1. Check userStakingData
    uint256 itemTimestamp = userStakingData.timestampMap[staker_][col_][
      tokenId_
    ];
    require(itemTimestamp > 0, "item not exists");
    require(
      ERC721(col_).ownerOf(tokenId_) == address(this),
      "vault not the owner"
    );
    // 2. calculate score
    ItemStakingStat memory stat = itemStakingStat(staker_, col_, tokenId_);
    // 3. safeTransferFrom (transfer Nft to msg.sender)
    ERC721(col_).safeTransferFrom(address(this), staker_, tokenId_);
    // 4. Remove data
    _removeStakedData(staker_, col_, tokenId_);
    // 5. append yo userHisScore
    userHistScore[staker_] += stat.score;
    emit NFTUnstaked(staker_, col_, tokenId_);
  }

  function unstake(address collection, uint256 tokenId) external nonReentrant {
    _unstakeSafe(msg.sender, collection, tokenId);
  }

  function userScore(address user) external view returns (UserScore memory) {
    uint256 itemStakingScores = 0;
    UserStakedItem[] memory items = userStakedItems(user);
    uint256[] memory tempOut = new uint256[](items.length);
    for (uint256 i = 0; i < items.length; i++) {
      address col = items[i].collection;
      uint256 tokenId = items[i].tokenId;
      ItemStakingStat memory stat = itemStakingStat(user, col, tokenId);
      itemStakingScores += stat.score;
      tempOut[i] = stat.score;
    }
    return UserScore(block.timestamp, userHistScore[user] + itemStakingScores);
  }

  function itemStakingStat(
    address user,
    address collection,
    uint256 tokenId
  ) public view returns (ItemStakingStat memory) {
    uint256 itemTimestamp = userStakingData.timestampMap[user][collection][
      tokenId
    ];
    require(itemTimestamp > 0, "item not exists");
    if (!EnumerableSet.contains(wlCol.colAddrSet, collection)) {
      return ItemStakingStat(0, 0);
    } 
    uint256 diff = block.timestamp - itemTimestamp;
    uint256 score = (diff / stakingInterval) * wlCol.colMap[collection].weight;
    return ItemStakingStat(diff, score);
  }

  function rescue(
    address user,
    address collection,
    uint256 tokenId
  ) external onlyOwner {
    _unstakeSafe(user, collection, tokenId);
  }
}
