// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "oz/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}