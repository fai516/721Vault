//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

abstract contract Mock721 is ERC721Enumerable {
  constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

  function mint() external {
    _mint(msg.sender, totalSupply());
  }

  function mintWithTokenId(uint256 tokenId) external {
    _mint(msg.sender, tokenId);
  }
}
