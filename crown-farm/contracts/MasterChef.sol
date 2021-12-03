// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.6.12;

import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import "./libraries/TransferHelper.sol";
import './libraries/k.sol';

contract MasterChef is KOwnerable {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 id;
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 depositTime;
        uint256 expireTime;
        uint ownerLastDrawTime;
        uint userEarned;
        uint unLockAmount;
        mapping (uint256 => bool) claimedOrderId;
        mapping (uint => uint) dayAmount;
        uint[] timeList;
        mapping(uint => uint) valueMapping;
        mapping( uint => uint) personDayValidLine;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        IERC20 earnToken;
        address pair;
        uint256 netAll;
        mapping (uint => uint) dayEarn;
        mapping (uint => uint) netAmount;
        uint[] timeList;
        mapping(uint => uint) valueMapping;
        mapping(uint => uint) networkDayValieLine;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping (address => uint) pairOfId;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => mapping (address => UserInfo[])) public userInfos;

    address internal zapIn;
    address internal swap;

    uint public constant MINIMUM_PERIOD = 7 days;

    uint internal constant depth = 10;

    event Deposit(address indexed user, uint256 indexed pid, uint256 sid, uint256 amount, uint t, uint expireTime, address pair);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 sid, uint256 amount);
    event EventClaim(uint256 pid, uint256 orderId, address userAddress,uint256 amount);

    constructor(address _swap) public {
        require(_swap != address(0), "address is 0");
        swap = _swap;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(IERC20 _lpToken, IERC20 _earnToken) external KOwnerOnly {
        (bool h,) = queryPairOfId(address(_lpToken));
        if (!h) {
            poolInfo.push(PoolInfo({
                lpToken: _lpToken,
                earnToken: _earnToken,
                pair: address(_lpToken),
                netAll: 0,
                timeList: new uint[](0)
            }));
            pairOfId[address(_lpToken)] = poolInfo.length - 1;
        }
    }

    function setZapIn(address _zapIn) external KOwnerOnly {
        require(_zapIn != address(0), "address is 0");
        zapIn = _zapIn;
    }

    function queryPairOfId(address _pair) public view returns (bool r, uint v) {
        if (_pair != address(0) && poolInfo.length > 0) {
            uint _id = pairOfId[_pair];
            return (poolInfo[_id].pair == _pair, _id);
        }
        return (false, 0);
    }

    function depositDelegate(address _depositor, uint256 _pid, uint256 _amount) external {
        require(msg.sender == zapIn, "delegate error");
        _deposit(_depositor, _pid, _amount);
    }

    function deposit(uint256 _pid, uint256 _amount) external KRejectContractCall {
        _deposit(msg.sender, _pid, _amount);
    }

    function _deposit(address _owner, uint256 _pid, uint256 _amount) internal {
        require (_pid < poolInfo.length, 'deposit _pid error');

        PoolInfo storage pool = poolInfo[_pid];
        uint256 deposit_id = userInfos[_pid][_owner].length;
        uint curTime = timestemp();
        uint expireTime = curTime.add(MINIMUM_PERIOD);
        userInfos[_pid][_owner].push(UserInfo({
            id: deposit_id,
            amount: _amount,
            depositTime: curTime,
            expireTime: expireTime,
            ownerLastDrawTime: 0,
            userEarned: 0,
            unLockAmount: 0,
            timeList: new uint[](0)
        }));

        if (_amount > 0) {
            pool.netAll += _amount;
            changeData(_pid, _owner, _amount, true);
            TransferHelper.safeTransferFrom(address(pool.lpToken), msg.sender, address(this), _amount);
        }
        emit Deposit(_owner, _pid, deposit_id, _amount, curTime, expireTime, pool.pair);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _drawAmount) external KRejectContractCall {

        require (_pid < poolInfo.length, 'deposit _pid error');
        require(_drawAmount > 0, "There is no deposit available!");
        
        UserInfo storage userall = userInfo[_pid][msg.sender];
        uint userLock = userLockAll(_pid, timestempZero());
        require(userLock > 0, "withdraw: not good");

        uint canDraw_ = _canDrawAmount(_pid) - userall.unLockAmount;
        require(canDraw_ >= _drawAmount, "withdraw: canDraw not good");

        PoolInfo storage pool = poolInfo[_pid];
        userall.unLockAmount += _drawAmount;
        pool.netAll = pool.netAll.sub(_drawAmount);
        changeData(_pid, msg.sender, _drawAmount, false);

        TransferHelper.safeTransfer(address(pool.lpToken), msg.sender, _drawAmount);

        emit Withdraw(msg.sender, _pid, 0, _drawAmount);
    }

    function depositInfo(uint _pid) external view returns (uint total, uint netTotal, uint canDraw, uint earn) {
        require (_pid < poolInfo.length, 'deposit _pid error');
        UserInfo storage userall = userInfo[_pid][msg.sender];
        canDraw = _canDrawAmount(_pid).sub(userall.unLockAmount);
        PoolInfo storage pool = poolInfo[_pid];
        total = userLockAll(_pid, timestempZero());
        netTotal = pool.netAll;
        earn = _settle(_pid);
    }

    function myDepositInfos(uint _pid) external view returns
        (uint total, uint netTotal, uint canDraw, uint earn, uint[] memory depositAmounts, uint[] memory startTime, uint[] memory expireTime) {
        require (_pid < poolInfo.length, 'deposit _pid error');
        UserInfo storage userall = userInfo[_pid][msg.sender];
        canDraw = _canDrawAmount(_pid).sub(userall.unLockAmount);
        UserInfo[] memory infos = userInfos[_pid][msg.sender];

        PoolInfo storage pool = poolInfo[_pid];
        total = userLockAll(_pid, timestempZero());

        depositAmounts = new uint[](infos.length);
        startTime = new uint[](infos.length);
        expireTime = new uint[](infos.length);
        for (uint i = 0; i < infos.length; i++) {
            depositAmounts[i] = infos[i].amount;
            startTime[i] = infos[i].depositTime;
            expireTime[i] =  infos[i].expireTime;
        }
        netTotal = pool.netAll;
        earn = _settle(_pid);
    }

    function _canDrawAmount(uint _pid) internal view returns (uint v) {
        UserInfo[] memory infos = userInfos[_pid][msg.sender];
        uint curtime = timestemp();
        for (uint i = 0; i < infos.length; i++) {
            if (curtime > infos[i].expireTime) {
                v += infos[i].amount;
            }
        }
    }

    function updateEarn(uint _amount, address _pair) external returns (bool) {
        require(msg.sender == swap, "swap error");

        (bool h,) = queryPairOfId(_pair);
        if (!h) {
            return false;
        }
        uint _pid = pairOfId[_pair];
        PoolInfo storage pool = poolInfo[_pid];
        pool.dayEarn[timestempZero()] += _amount;

        return true;
    }

    function getAwardInfo(uint _pid) 
        external view returns(uint netTotalEarn, uint netLastTotalEarn, uint userEarned, uint userEarn) {
        if (_pid < poolInfo.length) {
            UserInfo storage user = userInfo[_pid][msg.sender];
            PoolInfo storage pool = poolInfo[_pid];
            netTotalEarn =  pool.dayEarn[timestempZero()];
            netLastTotalEarn = pool.dayEarn[timestempZero() - 1 days];
            userEarned = user.userEarned;
            userEarn = _settle(_pid);
        }
    }

    function doDraw(uint _pid) external KRejectContractCall returns (bool) {
        uint _amount = _settle(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        if (_amount > 0 && pool.earnToken.balanceOf(address(this)) >= _amount) {
            UserInfo storage user = userInfo[_pid][msg.sender];
            user.userEarned += _amount;
            user.ownerLastDrawTime = timestempZero();
            TransferHelper.safeTransfer(address(pool.earnToken), msg.sender, _amount);
        }
        return true;
    }

    function _settle(uint _pid) internal view returns (uint v) {
        UserInfo[] memory infos = userInfos[_pid][msg.sender];
        if (infos.length == 0) {
            return 0;
        }
        UserInfo storage user = userInfo[_pid][msg.sender];
        PoolInfo storage pool = poolInfo[_pid];
        uint lastTime = user.ownerLastDrawTime;
        uint startTime = timestempZero() - 1 days;
        for ( uint index = depth; startTime >= lastTime && index > 0; (startTime -= 1 days,index--) ) {
            uint dayAmount = userLockAll(_pid, startTime);
            if (dayAmount == 0) {
                continue;
            }
            uint netAmount = netLockAll(_pid, startTime);
            v += ((dayAmount.mul(1e18)).div(netAmount).mul(pool.dayEarn[startTime])).div(1e18);
        }
    }

    function changeData(uint _pid, address owner, uint value, bool isAdd) internal {
        uint todayZero = timestempZero();

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage userall = userInfo[_pid][owner];

        if ( userall.ownerLastDrawTime == 0 ) {
            userall.ownerLastDrawTime = todayZero;
        }

        uint lastValue = 0;
        uint networkLastValue = 0;

        if ( isAdd ) {
            lastValue = _increase(_pid, owner, value, todayZero);
            networkLastValue = _increase1(_pid, value, todayZero);
        } else {
            lastValue = _decrease(_pid, owner, value, todayZero);
            networkLastValue = _decrease1(_pid, value, todayZero);
        }

        userall.personDayValidLine[todayZero] = lastValue;
        pool.networkDayValieLine[todayZero] = networkLastValue;
    }

    function _increase(uint _pid, address _owner, uint addValue, uint time) internal returns(uint){

        UserInfo storage user = userInfo[_pid][_owner];
        if( user.timeList.length == 0 ){
            user.timeList.push(time);
            user.valueMapping[time] = addValue;
            return addValue;
        }else{
            uint latestTime = user.timeList[user.timeList.length - 1];

            if (latestTime == time) {
                user.valueMapping[latestTime] += addValue;
                return user.valueMapping[latestTime];
            }else{
                uint v = user.valueMapping[latestTime];
                user.timeList.push(time);
                user.valueMapping[time] = (v + addValue);
                return user.valueMapping[time];
            }
        }
    }

    function _increase1(uint _pid, uint addValue, uint time) internal returns(uint) {
        PoolInfo storage pool = poolInfo[_pid];
        if( pool.timeList.length == 0 ){
            pool.timeList.push(time);
            pool.valueMapping[time] = addValue;
            return addValue;
        }else{
            uint latestTime = pool.timeList[pool.timeList.length - 1];

            if (latestTime == time) {
                pool.valueMapping[latestTime] += addValue;
                return pool.valueMapping[latestTime];
            }else{
                uint v = pool.valueMapping[latestTime];
                pool.timeList.push(time);
                pool.valueMapping[time] = (v + addValue);
                return pool.valueMapping[time];
            }
        }
    }


    function _decrease(uint _pid, address _owner, uint subValue, uint time) internal returns(uint){

        UserInfo storage user = userInfo[_pid][_owner];
        if( user.timeList.length != 0 ){

            uint latestTime = user.timeList[user.timeList.length - 1];

            uint v = user.valueMapping[latestTime];
            require(v >= subValue, "InsufficientQuota");

            if (latestTime == time) {
                v -= subValue;
                user.valueMapping[latestTime] = v;
                return v;
            } else {
                user.timeList.push(time);
                user.valueMapping[time] = ( v - subValue);
                return user.valueMapping[time];
            }
        }
        return 0;
    }

    function _decrease1(uint _pid, uint subValue, uint time) internal returns(uint){

        PoolInfo storage pool = poolInfo[_pid];
        if( pool.timeList.length != 0 ){

            uint latestTime = pool.timeList[pool.timeList.length - 1];

            uint v = pool.valueMapping[latestTime];
            require(v >= subValue, "InsufficientQuota");

            if (latestTime == time) {
                v -= subValue;
                pool.valueMapping[latestTime] = v;
                return v;
            } else {
                pool.timeList.push(time);
                pool.valueMapping[time] = ( v - subValue);
                return pool.valueMapping[time];
            }
        }
        return 0;
    }

    function _latestValue(uint[] storage timeList, mapping(uint => uint) storage valueMapping) internal view returns (uint) {
        uint[] storage s = timeList;
        if ( s.length <= 0 ) {
            return 0;
        }
        uint time = timeList[s.length-1];
        return valueMapping[time];
    }

    function userLockAll(uint _pid, uint zeroTime) internal view returns (uint v) {
        UserInfo storage userall = userInfo[_pid][msg.sender];
        v = userall.personDayValidLine[zeroTime];
        if (v == 0) {
            v = _bestMatchValue(userall.timeList, userall.valueMapping, zeroTime, depth);
        }
    }

    function netLockAll(uint _pid, uint zeroTime) internal view returns (uint v) {
        PoolInfo storage pool = poolInfo[_pid];
        v = pool.networkDayValieLine[zeroTime];
        if (v == 0) {
            v = _bestMatchValue(pool.timeList, pool.valueMapping, zeroTime, depth);
        }
    }

    function _bestMatchValue(
        uint[] storage timeList, mapping(uint => uint) storage valueMapping, uint time, uint _depth
    ) internal view returns(uint) {

        uint[] storage s = timeList;

        if (s.length == 0 || time < s[0]) {
            return 0;
        }

        for( 
            (uint i,uint d) = (s.length,0); 
            i > 0 && d < _depth; 
            ( i--,d++)){

            if( time >= s[i-1] ){
                return  valueMapping[s[i-1]];
            }
        }
        return 0;
    }
}
