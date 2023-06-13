//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Mock721.sol";

contract MockAzuki is Mock721 {
  constructor() Mock721("Azuki", "AZUKI") {}

  function _baseURI() internal pure override returns (string memory) {
    return "ipfs://QmZcH4YvBVVRJtdn4RdbaqgspFU8gH6P9vomDpBVpAL3u4/";
  }
}
