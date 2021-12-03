// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.6.12;

import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import "./libraries/TransferHelper.sol";
import './libraries/k.sol';

contract LockRelease is KOwnerable {
  using SafeMath for uint256;

  uint internal ownerLastDrawTime;
  uint internal dayMined;
  IERC20 internal lockToken;
  address internal to;

  constructor(address _token, uint _dayMined, address _to) public {
    dayMined = _dayMined;
    lockToken = IERC20(_token);
    ownerLastDrawTime = timestempZero();
    to = _to;
  }

  function _settle() internal view returns (uint v) {
    uint lastTime = ownerLastDrawTime;
    uint startTime = timestempZero() - 1 days;
    uint allDays = (startTime - lastTime) / 1 days;
    v = dayMined * allDays;
  }

  function drawInfo() external view returns (uint) {
    return _settle();
  }

  function withDraw() external {
      uint _amount = _settle();
      if (_amount > 0) {
        ownerLastDrawTime = timestempZero();
        TransferHelper.safeTransfer(address(lockToken), to, _amount);
      }
  }
}