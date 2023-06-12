//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Mock721 is ERC721Enumerable {
  constructor() ERC721("Mock721", "M721") {}

  function mint() external {
    _mint(msg.sender, totalSupply());
  }

  function mintWithTokenId(uint256 tokenId) external {
    _mint(msg.sender, tokenId);
  }
}
