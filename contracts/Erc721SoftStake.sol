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
  mapping(address => uint16) stakedMap;
}

struct UserStakedData {
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

struct StakedItemStat {
  uint256 elapsed;
  uint256 score;
}

struct UserScore {
  uint256 timestamp;
  uint256 permanentScore;
  uint256 sessionScore;
}

contract Erc721SoftStake is Ownable, ReentrancyGuard, ERC721Holder {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableSet for EnumerableSet.AddressSet;
  bytes4 public erc721InterfaceId = 0x80ac58cd;
  uint16 public maxStakedDay;
  bool public isStakingAllowed;
  uint32 public stakingInterval;
  uint256 public holding;
  address public operator;
  WhitelistedCollection internal wlCol;
  UserStakedData internal userStakedData;
  mapping(address => mapping(uint256 => address)) internal ownership;
  mapping(address => uint256) internal userPermanentScore;

  event StakingOpen();
  event StakingClose();
  event OperatorUpdated(address operator);
  event SetStakeInterval(uint32 interval);
  event SetMaxStakedDay(uint16 day);
  event SetWhitelistedCollection(
    address collection,
    uint16 quota,
    uint8 weight
  );
  event DeleteWhitelistedCollection(address collection);
  event VaultRecievedNft();
  event NFTStaked(
    address staker,
    address collection,
    uint256 tokenId,
    uint8 weight,
    uint256 timestamp
  );
  event NFTCheckIn(
    address staker,
    address collection,
    uint256 tokenId,
    uint8 weight,
    uint256 timestamp
  );
  event NFTUnstaked(
    address staker,
    address collection,
    uint256 tokenId,
    uint8 weight,
    uint256 timestamp
  );

  constructor(uint32 interval_, uint16 maxStakedDay_) {
    isStakingAllowed = false;
    stakingInterval = interval_;
    setStakeInterval(interval_);
    setMaxStakedDay(maxStakedDay_);
  }

  // constructor(uint32 interval_, uint16 maxStakedDay_) {
  //   isStakingAllowed = false;
  //   stakingInterval = interval_;
  //   setStakeInterval(interval_);
  //   setMaxStakedDay(maxStakedDay_);
  // }
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

  function setOperator(address addr) public onlyOwner {
    operator = addr;
    emit OperatorUpdated(addr);
  }

  function setMaxStakedDay(uint16 newValue) public onlyOwner {
    maxStakedDay = newValue;
    emit SetMaxStakedDay(newValue);
  }

  function setStakeInterval(uint32 newValue) public onlyOwner {
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
    returns (address[] memory, uint32[] memory, uint16[] memory, uint8[] memory)
  {
    uint256 size = EnumerableSet.length(wlCol.colAddrSet);
    address[] memory addrOut = new address[](size);
    uint32[] memory quotaOut = new uint32[](size);
    uint8[] memory weightOut = new uint8[](size);
    uint16[] memory stakedQuotaOut = new uint16[](size);
    for (uint256 i = 0; i < size; i++) {
      address addr = EnumerableSet.at(wlCol.colAddrSet, i);
      addrOut[i] = addr;
      quotaOut[i] = wlCol.colMap[addr].maxQuota;
      stakedQuotaOut[i] = wlCol.stakedMap[addr];
      weightOut[i] = wlCol.colMap[addr].weight;
    }
    return (addrOut, quotaOut, stakedQuotaOut, weightOut);
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
    uint256 itemTimestamp = userStakedData.timestampMap[addr_][col_][tokenId_];
    return itemTimestamp;
  }

  function _getUserStakedItems(
    address addr_
  ) internal view returns (UserStakedItem[] memory) {
    uint256 userStaked = userStakedData.staked[addr_];
    uint256 pointer = 0;
    UserStakedItem[] memory items = new UserStakedItem[](userStaked);
    EnumerableSet.AddressSet storage colSet = userStakedData.addrToColIndexing[
      addr_
    ];
    uint256 colSetLength = EnumerableSet.length(colSet);
    for (uint256 i = 0; i < colSetLength; i++) {
      address col = EnumerableSet.at(colSet, i);
      EnumerableSet.UintSet storage tokenIdSet = userStakedData
        .colToTokenIdIndexing[addr_][col];
      uint256 tokenIdSetLength = EnumerableSet.length(tokenIdSet);
      for (uint256 j = 0; j < tokenIdSetLength; j++) {
        uint256 tokenId = EnumerableSet.at(tokenIdSet, j);
        uint256 timestamp = userStakedData.timestampMap[addr_][col][tokenId];
        items[pointer++] = UserStakedItem(col, tokenId, timestamp);
      }
    }
    return items;
  }

  function _createStakedData(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    EnumerableSet.add(userStakedData.addrSet, staker_);
    EnumerableSet.add(userStakedData.addrToColIndexing[staker_], col_);
    EnumerableSet.add(
      userStakedData.colToTokenIdIndexing[staker_][col_],
      tokenId_
    );
    userStakedData.timestampMap[staker_][col_][tokenId_] = block.timestamp;
    wlCol.stakedMap[col_] += 1;
    holding += 1;
    userStakedData.staked[staker_] += 1;
  }

  function _removeStakedData(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    delete userStakedData.timestampMap[staker_][col_][tokenId_];
    EnumerableSet.remove(
      userStakedData.colToTokenIdIndexing[staker_][col_],
      tokenId_
    );
    if (
      EnumerableSet.length(userStakedData.colToTokenIdIndexing[staker_][col_]) <
      1
    ) {
      EnumerableSet.remove(userStakedData.addrToColIndexing[staker_], col_);
    }
    if (EnumerableSet.length(userStakedData.addrToColIndexing[staker_]) < 1) {
      delete userStakedData.addrToColIndexing[staker_];
      EnumerableSet.remove(userStakedData.addrSet, staker_);
    }
    wlCol.stakedMap[col_] -= 1;
    holding -= 1;
    userStakedData.staked[staker_] -= 1;
  }

  function itemOwnership(
    address collection,
    uint256 tokenId
  ) external view returns (address) {
    return ownership[collection][tokenId];
  }

  // TODO: scalable issue - what if address set is very large
  function users() external view returns (address[] memory) {
    uint256 len = EnumerableSet.length(userStakedData.addrSet);
    address[] memory out = new address[](len);
    for (uint256 i = 0; i < len; i++) {
      out[i] = EnumerableSet.at(userStakedData.addrSet, i);
    }
    return out;
  }

  function userStakedItems(
    address user
  ) public view returns (UserStakedItem[] memory) {
    return _getUserStakedItems(user);
  }

  function _isOnchainOwner(
    address addr_,
    address col_,
    uint256 id_
  ) internal view returns (bool) {
    address owner = ERC721(col_).ownerOf(id_);
    return owner == addr_;
  }

  function stake(
    address[] memory collections,
    uint256[] memory tokenIds
  ) external nonReentrant stakingOpened {
    uint256 len = collections.length;
    for (uint256 i = 0; i < len; i++) {
      _stakeSafe(collections[i], tokenIds[i]);
    }
  }

  function _stakeSafe(address col_, uint256 id_) internal {
    require(_isValidErc721Contract(col_), "not a valid erc-721 address");
    uint32 maxQuota = wlCol.colMap[col_].maxQuota;
    require(maxQuota > 0, "not whitelisted");
    require(
      wlCol.stakedMap[col_] + 1 <= maxQuota,
      "reach max quota of collection"
    );
    require(_isOnchainOwner(msg.sender, col_, id_), "not a owner");
    address localOwner = ownership[col_][id_];
    if (localOwner != address(0)) {
      if (localOwner != msg.sender) {
        _removeStakedData(localOwner, col_, id_);
      } else {
        revert("use check-in");
      }
    }
    // ERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
    _createStakedData(msg.sender, col_, id_);
    ownership[col_][id_] = msg.sender;
    emit NFTStaked(
      msg.sender,
      col_,
      id_,
      wlCol.colMap[col_].weight,
      block.timestamp
    );
  }

  function _singleCheckIn(address col_, uint256 id_) internal {
    uint256 itemTimestamp = userStakedData.timestampMap[msg.sender][col_][id_];
    require(itemTimestamp > 0, "item not exists");
    // require(ownership[collection][tokenId] == msg.sender, "not a owner");
    require(_isOnchainOwner(msg.sender, col_, id_), "not a onchain owner");
    StakedItemStat memory stat = _calculateCurrentItemStakedScore(
      msg.sender,
      col_,
      id_
    );
    userPermanentScore[msg.sender] += stat.score;
    userStakedData.timestampMap[msg.sender][col_][id_] = block.timestamp;
    emit NFTCheckIn(
      msg.sender,
      col_,
      id_,
      wlCol.colMap[col_].weight,
      block.timestamp
    );
  }

  function checkIn(
    address[] memory collections,
    uint256[] memory tokenIds
  ) external nonReentrant stakingOpened {
    uint256 len = collections.length;
    for (uint256 i = 0; i < len; i++) {
      _singleCheckIn(collections[i], tokenIds[i]);
    }
  }

  function _unstakeSafe(
    address staker_,
    address col_,
    uint256 tokenId_
  ) internal {
    uint256 itemTimestamp = userStakedData.timestampMap[staker_][col_][
      tokenId_
    ];
    require(itemTimestamp > 0, "item not exists");
    require(ownership[col_][tokenId_] == staker_, "not a owner");
    StakedItemStat memory stat = _calculateCurrentItemStakedScore(
      staker_,
      col_,
      tokenId_
    );
    _removeStakedData(staker_, col_, tokenId_);
    userPermanentScore[staker_] += stat.score;
    ownership[col_][tokenId_] = address(0);
    emit NFTUnstaked(
      staker_,
      col_,
      tokenId_,
      wlCol.colMap[col_].weight,
      block.timestamp
    );
  }

  function unstake(
    address[] memory collections,
    uint256[] memory tokenIds
  ) external nonReentrant {
    uint256 len = collections.length;
    for (uint256 i = 0; i < len; i++) {
      _unstakeSafe(msg.sender, collections[i], tokenIds[i]);
    }
  }

  function userScore(address user) external view returns (UserScore memory) {
    uint256 itemStakingScores = 0;
    UserStakedItem[] memory items = userStakedItems(user);
    uint256[] memory tempOut = new uint256[](items.length);
    for (uint256 i = 0; i < items.length; i++) {
      address col = items[i].collection;
      uint256 tokenId = items[i].tokenId;
      StakedItemStat memory stat = _calculateCurrentItemStakedScore(
        user,
        col,
        tokenId
      );
      itemStakingScores += stat.score;
      tempOut[i] = stat.score;
    }
    return
      UserScore(block.timestamp, userPermanentScore[user], itemStakingScores);
  }

  function _calculateCurrentItemStakedScore(
    address user_,
    address col_,
    uint256 id_
  ) internal view returns (StakedItemStat memory) {
    uint256 itemTimestamp = userStakedData.timestampMap[user_][col_][id_];
    require(itemTimestamp > 0, "item not exists");
    if (!EnumerableSet.contains(wlCol.colAddrSet, col_)) {
      return StakedItemStat(0, 0);
    }
    uint256 diff = block.timestamp - itemTimestamp;
    uint256 maxStakedSec = maxStakedDay * 86400;
    uint256 stakedSec = diff > maxStakedSec ? maxStakedSec : diff;
    uint256 score = (stakedSec / stakingInterval) * wlCol.colMap[col_].weight;
    return StakedItemStat(diff, score);
  }

  function itemStat(
    address user,
    address col,
    uint256 id
  ) public view returns (StakedItemStat memory) {
    return _calculateCurrentItemStakedScore(user, col, id);
  }

  // function rescue(
  //   address user,
  //   address collection,
  //   uint256 tokenId
  // ) external onlyOwner {
  //   _unstakeSafe(user, collection, tokenId);
  // }
}
