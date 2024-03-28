// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {GasMeter} from "./helper/GasMeter.sol";
import {ERC20Mintable} from "./common/ERC20Mintable.sol";
import {MockSettlement} from "./common/MockSettlement.sol";
import {SafeMath} from "oz/utils/math/SafeMath.sol";

import {GPv2Order} from "../src/libraries/GPv2Order.sol";
import {DCAOrder, NotOwner, NotWithinStartAndEndTimes} from "../src/DCAOrder.sol";
import {IConditionalOrder} from "../src/interfaces/IConditionalOrder.sol";

contract DCAOrderTest is Test, GasMeter {
  using GPv2Order for GPv2Order.Data;

  MockSettlement public mockSettlement;
  DCAOrder public dcaOrder;
  ERC20Mintable public sellToken;
  address public _owner;
  address public _receiver;
  address public _sellToken;
  address public _buyToken;
  uint256 public _interval;
  uint256 public _startTime;
  uint256 public _endTime;
  uint256 public _amount;

  // @todo: import from IConditionalOrder
  event ConditionalOrderCreated(address indexed);

  // @todo: import from DCAOrder
  event Initialized(address indexed order);
  event Cancelled(address indexed order);

  function setUp() public {
    mockSettlement = new MockSettlement();
    dcaOrder = new DCAOrder();
    sellToken = new ERC20Mintable('Test Token', 'TEST');
    sellToken.mint(address(this), 10000 ether);

    _owner = address(this);
    _receiver = address(0x2);
    _sellToken = address(sellToken);
    _buyToken = address(0x3);
    _interval = 1; // every 1 hours
    _startTime = block.timestamp + 1 hours;
    _endTime = _startTime + 1 days;
    _amount = 10 ether;
  }

  function testInitialize_success() public {
    vm.expectEmit(true, true, false, true, address(dcaOrder));
    emit ConditionalOrderCreated(address(dcaOrder));

    vm.expectEmit(true, true, false, true, address(dcaOrder));
    emit Initialized(address(dcaOrder));

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    // Assert all properties are set correctly
    assertEq(dcaOrder.owner(), _owner);
    assertEq(dcaOrder.receiver(), _receiver);
    assertEq(address(dcaOrder.sellToken()), address(sellToken));
    assertEq(address(dcaOrder.buyToken()), _buyToken);
    assertEq(dcaOrder.startTime(), _startTime);
    assertEq(dcaOrder.endTime(), _endTime);
    assertEq(dcaOrder.interval(), _interval);
    assertEq(dcaOrder.amount(), _amount);
    assertEq(dcaOrder.domainSeparator(), mockSettlement.domainSeparator());
  }

  function testInitialize_AlreadyInitialized() public {
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    vm.expectRevert(bytes4(keccak256("AlreadyInitialized()")));

    // Try to initialize again
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
  }

  function testInitialize_MissingOwner() public {
    vm.expectRevert(bytes4(keccak256("MissingOwner()")));

    dcaOrder.initialize(
      address(0), _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
  }

  function testInitialize_ReceiverIsOrder() public {
    vm.expectRevert(bytes4(keccak256("ReceiverIsOrder()")));

    dcaOrder.initialize(
      _owner,
      address(dcaOrder),
      _sellToken,
      _buyToken,
      _amount,
      _startTime,
      _endTime,
      _interval,
      address(mockSettlement)
    );
  }

  function testInitialize_IntervalMustBeGreaterThanZero() public {
    vm.expectRevert(bytes4(keccak256("IntervalMustBeGreaterThanZero()")));

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, 0, address(mockSettlement)
    );
  }

  function testInitialize_InvalidStartTime() public {
    vm.expectRevert(bytes4(keccak256("InvalidStartTime()")));

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, block.timestamp, _endTime, _interval, address(mockSettlement)
    );
  }

  function testInitialize_InvalidEndTime() public {
    vm.expectRevert(bytes4(keccak256("InvalidEndTime()")));

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, block.timestamp, _interval, address(mockSettlement)
    );
  }

  function testSlots() public {
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    uint256[] memory slots = dcaOrder.orderSlots();
    // In a 24 hour period, there should be 24 slots
    assertEq(slots.length, 24);
    // The first slot should be the startTime
    assertEq(slots[0], _startTime);
    // The last slot should be the endTime - 1 hour
    assertEq(slots[23], _endTime - 1 hours);
    // Between each slot, there should be an interval of 1 hour
    for (uint256 i = 0; i < slots.length - 1; i++) {
      assertEq(slots[i + 1] - slots[i], 1 hours);
    }
  }

  function testCanCancelOrder() public {
    sellToken.transfer(address(dcaOrder), _amount);
    // different clean address
    address newCleanOwner = address(0x10);

    dcaOrder.initialize(
      newCleanOwner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
    assertEq(sellToken.balanceOf(address(dcaOrder)), _amount);
    assertEq(sellToken.balanceOf(newCleanOwner), 0);

    vm.expectEmit(true, true, false, true, address(dcaOrder));
    emit Cancelled(address(dcaOrder));

    vm.prank(newCleanOwner);
    dcaOrder.cancel();
    // Balance should be 0
    assertEq(sellToken.balanceOf(address(dcaOrder)), 0);
    assertEq(sellToken.balanceOf(newCleanOwner), _amount);
  }

  function testCannotCancelOrderIfNotOwner() public {
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
    vm.prank(address(0x1));
    vm.expectRevert(NotOwner.selector);
    dcaOrder.cancel();
  }

  /// @dev add fuzzing to test the current slot
  function testCurrentSlot() public {
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
    vm.prank(address(0x1));

    // warp to 1 hour before the startTime
    vm.warp(dcaOrder.startTime() - 1 hours);
    // the current slot should be 0
    assertEq(dcaOrder.currentSlot(), 0);

    // warp to the startTime of the order
    vm.warp(dcaOrder.startTime());
    // the current slot should be the startTime
    assertEq(dcaOrder.currentSlot(), _startTime);
    // warp to 1 hour after the startTime
    vm.warp(dcaOrder.startTime() + 1 hours);
    assertEq(dcaOrder.currentSlot(), _startTime + 1 hours);
    // warp to 10 hours after the startTime
    vm.warp(dcaOrder.startTime() + 10 hours);
    assertEq(dcaOrder.currentSlot(), _startTime + 10 hours);
    // warp to 15 hours after the startTime
    vm.warp(dcaOrder.startTime() + 15 hours);
    assertEq(dcaOrder.currentSlot(), _startTime + 15 hours);
    // warp to 15 hours after the startTime, add a couple more seconds
    vm.warp(dcaOrder.startTime() + 15 hours + 5 seconds);
    assertEq(dcaOrder.currentSlot(), _startTime + 15 hours);
    // warp to the endTime of the order
    vm.warp(dcaOrder.endTime() - 0.5 hours);
    assertEq(dcaOrder.currentSlot(), _endTime - 1 hours);
    // warp to after the endTime of the order
    vm.warp(dcaOrder.endTime() + 0.1 hours);
    // should return 0
    assertEq(dcaOrder.currentSlot(), 0);
  }

  /// @dev add fuzzing to test the current slot
  function testGetTradeableOrder() public {
    uint256 _testAmount = 30 ether;

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _testAmount, _startTime, _endTime, _interval, address(mockSettlement)
    );
    vm.prank(address(0x1));

    // warp to 1 hour before the startTime
    vm.warp(dcaOrder.startTime() - 1 hours);
    // Should revert because the order is not tradeable
    vm.expectRevert(NotWithinStartAndEndTimes.selector);
    dcaOrder.getTradeableOrder();
    // the current slot should be 0
    assertEq(dcaOrder.currentSlot(), 0);
    // warp to the startTime of the order
    vm.warp(dcaOrder.startTime());

    GPv2Order.Data memory order = dcaOrder.getTradeableOrder();

    emit log_address(address(order.sellToken));

    assertEq(address(order.sellToken), _sellToken);
    assertEq(address(order.buyToken), _buyToken);

    uint256 orderSlots = dcaOrder.orderSlots().length;
    emit log_uint(uint256(order.sellAmount));
    emit log_uint(orderSlots);

    (, uint256 expectedOrderSellAmount) = SafeMath.tryDiv(_testAmount, orderSlots);
    assertEq(order.sellAmount, expectedOrderSellAmount);
    // warp to 5 hours after the endTime
    vm.warp(dcaOrder.endTime() + 5 hours);
    // Should revert because the order is not tradeable
    vm.expectRevert(NotWithinStartAndEndTimes.selector);
    order = dcaOrder.getTradeableOrder();
  }

  function testGetTradeableOrder_GasUsage() public {
    uint256 _testAmount = 30 ether;

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _testAmount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    // warp to the startTime of the order
    vm.warp(dcaOrder.startTime());

    gasMeterStart();
    dcaOrder.getTradeableOrder();
    uint256 gas = gasMeterStop();

    assertLt(gas, 40000);
  }

  function testGetTradeableOrder_GasUsage_2_years() public {
    // 2 year long hourly stack
    uint256 endTime = _startTime + (1 days * 365 * 2);
    uint256 interval = 1;
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, 30 ether, _startTime, endTime, interval, address(mockSettlement)
    );

    // warp to the startTime of the order
    vm.warp(dcaOrder.startTime());

    gasMeterStart();
    dcaOrder.getTradeableOrder();
    uint256 gas = gasMeterStop();

    assertLt(gas, 40000);
  }

  function testGetTradeableOrder_OrderCancelled() public {
    uint256 _testPrincipal = 30 ether;

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _testPrincipal, _startTime, _endTime, _interval, address(mockSettlement)
    );

    // Cancel the order
    dcaOrder.cancel();

    vm.expectRevert(bytes4(keccak256("OrderCancelled()")));
    dcaOrder.getTradeableOrder();
  }

  function testGetTradeableOrder_ZeroSellAmount() public {
    uint256 _testPrincipal = 0 ether;

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _testPrincipal, _startTime, _endTime, _interval, address(mockSettlement)
    );

    vm.warp(dcaOrder.startTime());
    vm.expectRevert(bytes4(keccak256("ZeroSellAmount()")));
    dcaOrder.getTradeableOrder();
  }

  function testHourlyOverWeeksDCAOrders() public {
    _endTime = _startTime + 6 weeks;

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );
    // In a 6 week period, there should be 6 * 7 * 24 = 1008 slots
    uint256[] memory slots = dcaOrder.orderSlots();
    assertEq(slots.length, 1008);
  }

  function testDailyOverWeeksDCAOrders() public {
    _endTime = _startTime + 6 weeks;
    dcaOrder.initialize(
      _owner,
      _receiver,
      _sellToken,
      _buyToken,
      _amount,
      _startTime,
      _endTime,
      24, // 1 day
      address(mockSettlement)
    );
    // In a 6 week period, there should be 6 * 7 = 42 slots
    uint256[] memory slots = dcaOrder.orderSlots();
    assertEq(slots.length, 42);
  }

  function testEveryThreeDaysInWeeksDCAOrders() public {
    _endTime = _startTime + 12 weeks;
    dcaOrder.initialize(
      _owner,
      _receiver,
      _sellToken,
      _buyToken,
      _amount,
      _startTime,
      _endTime,
      24 * 3, // 3 days
      address(mockSettlement)
    );
    // in a 12 week period where buys are every 3 days, there should be 12 * 7 / 3 = 28 slots
    uint256[] memory slots = dcaOrder.orderSlots();
    assertEq(slots.length, 28);
  }

  /// @dev add fuzzing to test the current slot
  function testOrderLeftover() public {
    // big amount for testing edge cases where there is some leftover
    uint256 _testAmount = 31.434343536565656434 ether;
    sellToken.transfer(address(dcaOrder), _testAmount);

    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _testAmount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    uint256 orderSlotsLength = dcaOrder.orderSlots().length;
    // warp to the startTime of the order
    for (uint256 i = 0; i < orderSlotsLength; i++) {
      vm.warp(dcaOrder.startTime() + i * 1 hours);

      uint256 balanceBeforeTransfer = sellToken.balanceOf(address(dcaOrder));

      GPv2Order.Data memory order = dcaOrder.getTradeableOrder();
      vm.prank(address(dcaOrder));
      // fake token transfer
      sellToken.transfer(address(0x10), order.sellAmount);

      (, uint256 expectedOrderSellAmount) = SafeMath.tryDiv(_testAmount, orderSlotsLength);

      if (i == orderSlotsLength - 1) assertEq(order.sellAmount, balanceBeforeTransfer);
      else assertEq(order.sellAmount, expectedOrderSellAmount);
    }
    assertEq(sellToken.balanceOf(address(dcaOrder)), 0);
  }

  function testisValidSignature() public {
    dcaOrder.initialize(
      _owner, _receiver, _sellToken, _buyToken, _amount, _startTime, _endTime, _interval, address(mockSettlement)
    );

    // Advances block.timestamp by n seconds
    skip(3601);

    bytes32 orderDigest = dcaOrder.getTradeableOrder().hash(dcaOrder.domainSeparator());
    bytes memory encodedOrder = abi.encode(dcaOrder.getTradeableOrder());
    bytes4 output = dcaOrder.isValidSignature(orderDigest, encodedOrder);
    assertTrue(output == 0x1626ba7e);
  }
}
