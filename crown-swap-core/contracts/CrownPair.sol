pragma solidity =0.5.16;

import './interfaces/ICrownPair.sol';
import './CrownERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/ICrownFactory.sol';
import './interfaces/ICrownCallee.sol';

contract CrownPair is ICrownPair, CrownERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
    uint32 public swapFee = 25; // uses 0.25% fee as default
    uint32 public constant sellFee = 500;
    address public baseToken;
    bool internal mined = true;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Crown: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Crown: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    event EBuy(uint amountIn, uint amountOut, bool _isBuy, uint amount, uint fee);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'Crown: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    function getSwapFee(address token) external view returns (uint fee, bool isBuy) {
        if (baseToken == address(0)) {
            return (swapFee, true);
        }
        (fee, isBuy) = token == baseToken ?(swapFee, true) :(swapFee, false);
    }

    function setBaseToken(address token) external {
        require(msg.sender == factory, 'Crown: FORBIDDEN'); // sufficient check
        require(token != address(0), 'Crown: FORBIDDEN_FEE'); // fee percentage check
        baseToken = token;
    }

    function getMined() external view returns (bool) {
        return mined;
    }

    function setMined(bool _mined) external {
        require(msg.sender == factory, 'Crown: FORBIDDEN'); // sufficient check
        mined = _mined;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'Crown: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = ICrownFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(3).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'Crown: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        require(totalSupply != 0, "The value of totalSupply must not be 0");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Crown: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function isBuy(uint amount0Out) private view returns (bool isBuy_, address feeToken) {
        address token = amount0Out > 0 ?token1 :token0;
        isBuy_ = token == baseToken;
        if (baseToken == address(0) || isBuy_) {
            isBuy_ = true;
            feeToken = amount0Out > 0 ?token0 :token1;
        } else {
            isBuy_ = false;
            feeToken = baseToken == token0 ?token1 :token0;
        }
    }

    function _transferFee(uint amountIn, uint amountOut, bool _isBuy, address feeToken) private returns (uint fee, uint sfee) {
        require(ICrownFactory(factory).getReserve(address(this)) != address(0));
        require(ICrownFactory(factory).getPledge(address(this)) != address(0));
        require(ICrownFactory(factory).getBurn(address(this)) != address(0));
        require(ICrownFactory(factory).getTop100(address(this)) != address(0));
        require(ICrownFactory(factory).getVisit(address(this)) != address(0));
        require(ICrownFactory(factory).getMarketAddress(address(this)) != address(0));

        uint reserve_;
        uint burn_;
        uint pledge_;
        uint top100_;
        uint feeEarn_;

        uint amount = _isBuy ?(amountOut*10000/9975) :amountIn;

        fee = amount.mul(swapFee) / 10000;
        burn_ = fee.mul(75) / 100;
        reserve_ = fee.mul(10) / 100;
        feeEarn_ = reserve_;
        top100_ = fee.mul(5) / 100;

        _safeTransfer(feeToken, ICrownFactory(factory).getReserve(address(this)), reserve_);
        _safeTransfer(feeToken, ICrownFactory(factory).getTop100(address(this)), top100_);
        _safeTransfer(feeToken, ICrownFactory(factory).getVisit(address(this)), feeEarn_);

        if (!_isBuy && mined) {
            sfee = amountIn.mul(sellFee) / 10000;
            fee += sfee;
            burn_ += sfee.mul(80) / 100;
            pledge_ = sfee.mul(10) / 100;
            _safeTransfer(feeToken, ICrownFactory(factory).getPledge(address(this)), pledge_);
            _safeTransfer(feeToken, ICrownFactory(factory).getMarketAddress(address(this)), pledge_);
            sfee = 0;
        }

        _safeTransfer(feeToken, ICrownFactory(factory).getBurn(address(this)), burn_);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'Crown: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Crown: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'Crown: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) ICrownCallee(to).crownCall(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Crown: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
         (bool _isBuy,) = isBuy(amount0Out);
         if (!_isBuy) {_checkSell(balance0, balance1, amount0In, amount1In, _reserve0, _reserve1);}
         else {_checkBuy(balance0, balance1, amount1Out, amount0Out, _reserve0, _reserve1);}
        }
        
        {
            (uint fee, bool _isBuy) = lastStep(amount0In, amount1In, amount0Out, amount1Out);
            if (_isBuy) { if (amount0Out > 0) {balance0 = balance0.sub(fee);} else {balance1 = balance1.sub(fee);} }
            else { if (amount1Out > 0) {balance0 = balance0.sub(fee);} else {balance1 = balance1.sub(fee);} }
         }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function calAmount(uint in0, uint in1, uint out0, uint out1) private pure returns (uint amountIn, uint out) {
        amountIn = in0 > in1 ?in0 :in1;
        out = out0 > out1 ?out0 :out1;
    }

    function _checkSell(
        uint balance0, uint balance1, uint amount0In, uint amount1In, uint112 _reserve0, uint112 _reserve1) internal pure {
        uint balance0Adjusted = balance0.mul(10000);
        uint balance1Adjusted = balance1.mul(10000);
        uint amountOut = amount0In > amount1In ?amount0In :amount1In;
        
        require(balance0Adjusted.mul(balance1Adjusted).sub(amountOut.mul(525)) >= uint(_reserve0).mul(_reserve1).mul(10000**2), 'Crown: K');
    }

    function _checkBuy(
        uint balance0, uint balance1, uint amount0Out, uint amount1Out, uint112 _reserve0, uint112 _reserve1) internal view {
        uint amountOut = amount0Out > 0 ?amount0Out :amount1Out;
        uint balance0Adjusted = balance0.mul(10000);
        uint balance1Adjusted = balance1.mul(10000);
        
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(10000**2).sub(amountOut.mul(swapFee)), 'Crown: K');
    }

    function lastStep(uint in0, uint in1, uint out0, uint out1) internal returns (uint fee, bool _isBuy) {
        (bool isBuy_, address feeToken) = isBuy(out0);
        (uint amountIn, uint out) = calAmount(in0, in1, out0, out1);
        _isBuy = isBuy_;
        (fee,) = _transferFee(amountIn, out, isBuy_, feeToken);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
