//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Mock721.sol";

contract MockApes is Mock721 {
  constructor() Mock721("BoredApeYachtClub", "BAYC") {}

  function _baseURI() internal pure override returns (string memory) {
    return "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/";
  }
}
