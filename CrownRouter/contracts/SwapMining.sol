// SPDX-License-Identifier: MIT

pragma solidity =0.6.6;

import "./libraries/k.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/ICrownFactory.sol";
import "./interfaces/ICrownPair.sol";
import './interfaces/ICrownRouter02.sol';

interface IRanking {
    function addPower(address _owner, uint _amount, uint _fee) external;
}

interface ILPPledge {
    function updateEarn(uint _amount, address _pair) external returns (bool);
}

contract SwapMining is KOwnerable {
    using SafeMath for uint256;

    address public router;
    // factory address
    ICrownFactory public factory;

    mapping(address => uint256) public pairOfPid;
    uint internal depth = 5;
    uint public rate = 1010;
    mapping (uint => uint) dayRate;
    uint internal numerator = 1000;
    uint internal delay = 20 hours;

    struct UserInfo {
        uint256 quantity;       // How many LP tokens the user has provided
        uint256 blockNumber;    // Last transaction block
        mapping (uint => uint) dayPower;
        mapping (uint => uint) dayLastSwap;
        uint ownerLastDrawTime;
        uint earned;
    }

    struct PoolInfo {
        address pair;           // Trading pairs that can be mined
        address earnToken;
        mapping (uint256 => uint256) quantity;
        uint256 totalQuantity;
        mapping (uint256 => uint256) dayPower;
        mapping (uint256 => uint256) lp24Earn;
        uint totalPower;
        uint256 allocPoint;     // How many allocation points assigned to this pool
        uint netEarned;
        uint256 burn;
        address ranking;
        address lpPledge;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event TXF(address user, address pair, uint fee, uint fee1, bool buy, uint timestemp);

    constructor( ICrownFactory _factory, address _router) public {
        require(address(_factory) != address(0) && _router != address(0), "address is 0");
        factory = _factory;
        router = _router;
        dayRate[timestempZero()] = rate;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function queryPairOfId(address _pair) public view returns (bool r, uint v) {
        if (_pair != address(0) && poolInfo.length > 0) {
            uint _id = pairOfPid[_pair];
            return (poolInfo[_id].pair == _pair, _id);
        }
        return (false, 0);
    }

    function addPair(
        address _pair, address _earnToken, address _ranking, address _lpPledge, uint _allocPoint) external KOwnerOnly {
        require(_pair != address(0) && _ranking != address(0) && _lpPledge != address(0), "address is the zero address");

        (bool h,) = queryPairOfId(_pair);
        if (!h) {
            poolInfo.push(PoolInfo({
                pair : _pair,
                earnToken: _earnToken,
                totalQuantity : 0,
                totalPower: 0,
                allocPoint : _allocPoint,
                netEarned: 0,
                burn: 0,
                ranking: _ranking,
                lpPledge: _lpPledge
            }));
            pairOfPid[_pair] = poolLength() - 1;
        }
    }

    // swapMining only router
    function swap(
        address account, address input, address output, uint256 amountOut, uint256 amountIn) external onlyRouter returns (bool) {
        require(account != address(0), "SwapMining: taker swap account is the zero address");
        require(input != address(0), "SwapMining: taker swap input is the zero address");
        require(output != address(0), "SwapMining: taker swap output is the zero address");

        address pair = ICrownFactory(factory).getPair(input, output);
        (bool h,) = queryPairOfId(pair);
        if (!h) {
            return false;
        }

        lastStep(amountIn, amountOut, account, input, pair);
        
        return true;
    }

    function lastStep(uint256 amountIn, uint256 amountOut, address account, address input, address pair) internal {

        uint[] memory poolData_ = new uint[](7);
        (bool isBuy, uint[] memory feeData) = calBurnFee(amountIn, amountOut, input, pair);
        {
            uint dayZero = timestempZero();
            poolData_[0] = pairOfPid[pair];
            poolData_[1] = dayZero;
            poolData_[2] = isBuy ?amountIn :amountOut; // swap
            poolData_[4] = feeData[3]; // top100
            poolData_[5] = feeData[4]; // pledge
        }

        {
            uint power;
            if (isBuy) {
                power = amountIn.mul(25).div(10000);
            } else {
                uint sfee = amountIn.mul(525).div(10000);
                uint price = amountOut.mul(1e18).div(amountIn.sub(sfee));
                power = sfee.mul(price).div(1e18);
            }
            poolData_[6] = power;
        }

        updatePool(poolData_, account, pair, isBuy);
        
        emit TXF(account, pair, feeData[2], poolData_[6], isBuy, timestemp());
    }

    function updatePool(uint[] memory data, address account, address pair, bool isBuy) internal {
        uint _pid = data[0];
        PoolInfo storage pool = poolInfo[_pid];

        pool.quantity[data[1]] += data[2];
        pool.totalQuantity += data[2];
        uint dayZero = timestempZero();
        userInfo[_pid][account].dayPower[dayZero] += data[6];
        userInfo[_pid][account].dayLastSwap[dayZero] = timestemp();
        pool.dayPower[data[1]] += data[6];
        pool.totalPower += data[6];

        if (pool.ranking != address(0)) {
            IRanking(pool.ranking).addPower(account, data[6], data[4]);
        }
        if (pool.lpPledge != address(0) && !isBuy) {
            pool.lp24Earn[data[1]] += data[5];
            ILPPledge(pool.lpPledge).updateEarn(data[5], pair);
        }
        if (userInfo[_pid][account].ownerLastDrawTime == 0) {
            userInfo[_pid][account].ownerLastDrawTime = dayZero;
        }
        if (dayRate[dayZero] == 0) {
            dayRate[dayZero] = rate;
        }
    }

    function calBurnFee(uint256 amountIn, uint256 amountOut, address input, address pair)
        internal view returns (bool isBuy, uint[] memory v) {
        
        v = new uint[](5);
        uint swapFee = 25;
        uint sellFee = 500;

        (swapFee, isBuy) = ICrownPair(pair).getSwapFee(input);

        uint amount = isBuy ?(amountOut*10000/(10000-swapFee)) :amountIn;
        v[0] = amount;
        uint fee = amount.mul(swapFee) / 10000;
        v[2] = fee.mul(10) / 100;
        v[3] = fee.mul(5) / 100;

        if (!isBuy) {
            uint sfee = amountIn.mul(sellFee) / 10000;
            v[4] = sfee.mul(10) / 100;
        }
    }

    function priceA2B(address input, address output) internal view returns (uint) {
       return price(input, output);
    }

    function priceB2A(address input, address output) internal view returns (uint) {
        return price(output, input);
    }

    function price(address input, address output) internal view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = input;
        path[1] = output;
        uint[] memory amounts = ICrownRouter02(router).getAmountsOut(
            1e18,
            path
        );
        return amounts[1];
    }

    // Get details of the pool
    function getPoolInfo(address _pair) public view returns (uint totalPower, uint earn, uint lp24Earn, uint swap, uint burn) {
        require(_pair != address(0), "getPoolInfo address is 0");
        uint _pid = pairOfPid[_pair];
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        uint zeroTime = timestempZero();
        PoolInfo storage pool = poolInfo[_pid];
        totalPower = _allPower(_pid, msg.sender);
        (earn,) = _settle(_pid, msg.sender);
        swap = pool.quantity[zeroTime];
        burn = pool.burn;
        lp24Earn = pool.lp24Earn[zeroTime];
    }

    function doDraw(address _pair) external KRejectContractCall returns (bool) {
        require(_pair != address(0), "getPoolInfo address is 0");
        uint _pid = pairOfPid[_pair];
        require(_pid <= poolInfo.length - 1, "doDraw: Not find this pool");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage _userInfo = userInfo[_pid][msg.sender];
        (uint _power, uint lt) = _settle(_pid, msg.sender);
        if (_power > 0) {
            uint _price = _AtoBAmount(_pair, pool.earnToken);
            uint _amount = _power.mul(1e18).div(_price);
            _userInfo.earned += _amount;
            pool.netEarned += _amount;
            _userInfo.ownerLastDrawTime = lt;
            TransferHelper.safeTransfer(pool.earnToken, msg.sender, _amount);
        }
        return true;
    }

    function _AtoBAmount(address pair, address priceToken) internal view returns (uint _price) {
        address input = inputToken(pair, priceToken);
        (uint a, uint b) = getReserves(pair, input, priceToken);
        _price = a.mul(1e18).div(b);
    }

    function inputToken(address pair, address priceToken) internal view returns (address input) {
        address token0 = ICrownPair(pair).token0();
        address token1 = ICrownPair(pair).token1();
        input = token0 == priceToken ?token1 :token0;
    }

    modifier onlyRouter() {
        require(msg.sender == router, "SwapMining: caller is not the router");
        _;
    }

    function _settle(uint _pid, address _user) internal view returns (uint v, uint lt) {
        UserInfo storage _userInfo = userInfo[_pid][_user];
        uint _dayZero = timestempZero();
        uint startPeriod = _dayZero - 1 days;
        uint lastPeriod = _userInfo.ownerLastDrawTime;
        for ( uint index = depth; startPeriod >= lastPeriod && index > 0; (startPeriod -= 1 days,index--) ) {
            uint lastSwapTime = _userInfo.dayLastSwap[startPeriod];
            if (timestemp() > (lastSwapTime + delay)) {
                uint power = _userInfo.dayPower[startPeriod];
                v += power.mul(dayRate[startPeriod]).div(numerator);
            } else if (lastSwapTime > 0 && lt == 0) {
                lt = startPeriod;
            }
        }
        if (lt == 0) {
            lt = _dayZero;
        }
    }

    function _allPower(uint _pid, address _user) internal view returns (uint v) {
        UserInfo storage _userInfo = userInfo[_pid][_user];
        uint startPeriod = timestempZero();
        v = _userInfo.dayPower[startPeriod];
        startPeriod -= 1 days;
        for ( uint index = depth; index > 0; (startPeriod -= 1 days,index--) ) {
            uint lastSwapTime = _userInfo.dayLastSwap[startPeriod];
            uint time = timestemp();
            if (time < (lastSwapTime + delay)) {
                v += _userInfo.dayPower[startPeriod];
            }
        }
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'sortTokens: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'sortTokens: ZERO_ADDRESS');
    }

    function getReserves(address pair, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = ICrownPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}
