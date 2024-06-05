// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import 'forge-std/Script.sol';
import '../src/DCAOrder.sol';
import '../src/OrderFactory.sol';

contract Deploy is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);

    new DCAOrder();
    new OrderFactory();

    vm.stopBroadcast();
  }
}
