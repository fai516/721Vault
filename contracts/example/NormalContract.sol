//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/AccessControl.sol";

// Suppose this contract does not support ERC-165
contract NormalContract {
  constructor() {}

  function hi() external pure returns (string memory name) {
    return "hi";
  }
}
