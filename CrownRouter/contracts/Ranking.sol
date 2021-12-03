// SPDX-License-Identifier: MIT

pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/k.sol";
import "./interfaces/IERC20.sol";
import "./libraries/TransferHelper.sol";

contract Ranking is KOwnerable {
    struct TopInfo {
        address owner;
        uint power;
    }

    mapping(uint => mapping(uint => TopInfo)) userTopInfo;
    mapping(uint => mapping(address => uint)) userIndexOfAddr;

    mapping(uint => TopInfo[]) sortedTopInfo;

    mapping(address => mapping(uint => uint)) public scores;
    mapping(uint => uint) internal allFee;
    mapping(address => mapping(uint => uint)) public earned;
    mapping(uint => uint) public netEarned;
    mapping(uint => uint) public lastEarn;
    mapping(address => uint) ownerLastDrawTime;
    mapping(uint => uint) internal listSize;

    uint internal startTime;
    uint internal constant top100 = 100;
    uint internal constant depth = 10;
    uint[] internal rateData = [200, 100, 50, 50, 30];
    address internal earnToken;
    address internal swap;

    event RK(address _owner, uint _amount);

    constructor(address _earnToken, address _swap) public {
        require(_earnToken != address(0) && _swap != address(0), "address set 0");
        uint period = curPeriod();
        startTime = timestempZero();
        lastEarn[period] = 0;
        earnToken = _earnToken;
        swap = _swap;
    }

    function addPower(
        address _owner,
        uint _amount,
        uint _fee
    ) public {
        require(msg.sender == swap, "call address error");
        if (_amount > 0) {
            uint period = curPeriod();
            addUserData(_owner, _amount, period);
            allFee[period] += _fee;
            _lastEarn(period);
        }
    }

    function _userIndex(address _owner, uint _power)
        internal
        view
        returns (bool f, uint v)
    {
        uint period = curPeriod();
        f = false;
        if (listSize[period] >= top100) {
            uint _userPower = scores[_owner][period] + _power;
            for (uint i = 0; i < top100; i++) {
                TopInfo memory _info = userTopInfo[period][i];
                if (_userPower >= _info.power) {
                    v = i;
                    f = true;
                    _userPower = _info.power;
                }
            }
            if (f) {
                uint index = userIndexOfAddr[period][_owner];
                if (userTopInfo[period][index].owner == _owner) {
                    v = index;
                }
            }
        } else {
            f = true;
            v = userIndexOfAddr[period][_owner];
            if (scores[_owner][period] == 0) { // not exsit
                v = listSize[period];
            }
        }
    }

    function addUserData(
        address _owner,
        uint _power,
        uint period
    ) internal {
        (bool f, uint _index) = _userIndex(_owner, _power);
        if (
            scores[_owner][period] == 0
        ) {
            listSize[period] += 1;
        }
        scores[_owner][period] += _power;
        if (f) {
            if (userTopInfo[period][_index].owner != _owner) {
                // not exsit
                userTopInfo[period][_index].owner = _owner;
                userIndexOfAddr[period][_owner] = _index;
            }
            userTopInfo[period][_index].power = scores[_owner][period];
        }
    }

    function _lastEarn(uint period) internal {
        if (period > 0 && lastEarn[period - 1] == 0) {
            lastEarn[period - 1] = allFee[period - 1] / 2 + lastEarn[period - 1] / 2;
        }
    }

    function getTop()
        external
        view
        returns (
            uint all,
            TopInfo[] memory topData
        )
    {
        uint period = curPeriod();
        all = allFee[period];
        topData = _rankTop(period);
    }

    function _rankTop(uint period)
        internal
        view
        returns (TopInfo[] memory topData)
    {
        if (period > 0 && sortedTopInfo[period - 1].length > 0) {
          topData = sortedTopInfo[period - 1];
        } else {
          topData = sortTopInfo(period);
        }
    }

    function curPeriod() public view returns (uint v) {
        v = (timestempZero() - startTime) / 7 days;
    }

    function getAwardInfo() external view returns ( uint netTotalEarn, uint netAllEarned, uint netNextEarn, uint userEarned, uint userEarn) {
        uint period = curPeriod();
        netTotalEarn = period > 0 ? periodAllEarn(period) : allFee[period] / 2;
        netAllEarned = netEarned[period];
        netNextEarn = period > 0 ? periodAllEarn(period) : allFee[period] / 2;
        userEarned = earned[msg.sender][period];
        userEarn = _settle(msg.sender);
    }

    function doDraw() external returns (bool) {
        uint period = curPeriod();
        _lastEarn(period);
        handleSortedInfo(period);
        uint _amount = _settle(msg.sender);
        if (_amount > 0 && IERC20(earnToken).balanceOf(address(this)) >= _amount) {
            earned[msg.sender][period] += _amount;
            netEarned[period] += _amount;
            ownerLastDrawTime[msg.sender] = period;
            TransferHelper.safeTransfer(earnToken, msg.sender, _amount);
        }
        return true;
    }

    function _findTop(address _user, uint period)
        internal
        view
        returns (bool isTop, uint topIndex)
    {
        TopInfo[] memory data = _rankTop(period);
        for (uint i = 0; i < data.length; i++) {
            if (_user == data[i].owner) {
                isTop = true;
                topIndex = i;
                break;
            }
        }
    }

    function _rate(uint _topIndex) internal view returns (uint v) {
        if (_topIndex >= rateData.length) {
            v = 6;
        } else {
            v = rateData[_topIndex];
        }
    }

    function _settle(address _user) internal view returns (uint v) {
        uint period = curPeriod();
        if (period > 0) {
            uint lastPeriod = ownerLastDrawTime[_user];
            uint startPeriod = period - 1;
            for (
                uint index = depth;
                startPeriod >= lastPeriod && index > 0;
                (startPeriod -= 1, index--)
            ) {
                (bool isTop, uint topIndex) = _findTop(_user, startPeriod);
                if (isTop) {
                    uint all = periodAllEarn(startPeriod);
                    v += (all * _rate(topIndex)) / 1000;
                }
                if (startPeriod == 0) {
                    break;
                }
            }
        }
    }

    function periodAllEarn(uint _period)
        internal
        view
        returns (uint all)
    {
        all = (allFee[_period] / 2) + (lastEarn[_period - 1] / 2);
    }

    function handleSortedInfo(uint period) internal {
        if (period > 0 && sortedTopInfo[period - 1].length == 0) {
            TopInfo[] memory data = sortTopInfo(period - 1);
            for (uint i = 0; i < data.length; i++) {
                sortedTopInfo[period - 1].push(data[i]);
            }
        }
    }

    function sortTopInfo(uint period) internal view returns (TopInfo[] memory data) {
      uint size = listSize[period];
      if (size > 0 && sortedTopInfo[period].length == 0) {
        uint len = size > top100 ? top100 : size;
        TopInfo[] memory allTopInfo = new TopInfo[](len);
        for (uint i = 0; i < len; i++) {
          allTopInfo[i] = userTopInfo[period][i];
        }
        data = sort(allTopInfo);
      }
    }

    function sort(TopInfo[] memory input)
        internal
        pure
        returns (TopInfo[] memory)
    {
        if (input.length >= 2) {
            sort(input, 0, int256(input.length - 1));
        }
        return input;
    }

    function sort(
        TopInfo[] memory arr,
        int256 left,
        int256 right
    ) internal pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        TopInfo memory pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)].power > pivot.power) i++;
            while (pivot.power > arr[uint(j)].power) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (
                    arr[uint(j)],
                    arr[uint(i)]
                );
                i++;
                j--;
            }
        }

        if (left < j) sort(arr, left, j);
        if (i < right) sort(arr, i, right);
    }
}