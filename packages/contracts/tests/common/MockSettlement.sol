// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockSettlement {
  function vaultRelayer() public pure returns (address) {
    return address(0x24);
  }

  function domainSeparator() public pure returns (bytes32) {
    return bytes32(0x0);
  }
}
