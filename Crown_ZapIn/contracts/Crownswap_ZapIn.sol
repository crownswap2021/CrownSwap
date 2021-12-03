
// SPDX-License-Identifier: GPL-2.0

pragma solidity 0.8.4;
import "./ZapInBaseV3.sol";
import "./SafeMath.sol";

interface IMasterChef {
    function depositDelegate(address _depositor, uint256 _pid, uint256 _amount) external;
    function queryPairOfId(address _pair) external view returns (bool r, uint v);
}

interface ICrownFactory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address);
}

interface ICrownRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) external view returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
}

interface ICrownPair {
    function token0() external pure returns (address);

    function token1() external pure returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}

contract Crownswap_ZapIn is ZapInBaseV3 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    mapping (address => address) internal reserveAddr;
    mapping (address => address) internal reserve1Addr;
    mapping (address => address) internal burnAddr;
    uint internal _buyRate = 40;
    uint internal _reserveRate = 10;

    ICrownFactory private constant crownswapFactoryAddress =
        ICrownFactory(0x37bf984b3FE990a44d8D2DdF017916F5bFFD5944);

    ICrownRouter private constant crownswapRouter =
        ICrownRouter(0x53A89d864D08833826f8F7bF2C2EC172DdB9a775);

    uint256 private constant deadline =
        0xf000000000000000000000000000000000000000000000000000000000000000;

    address internal masterChef;

    constructor(address _masterChef) public {
        require(_masterChef != address(0), "address is 0");
        masterChef = _masterChef;
    }

    event zapIn(address sender, address pool, uint256 tokensRec);

    /**
    @notice Add liquidity to Crownswap pools with ETH/ERC20 Tokens
    @param _FromTokenContractAddress The ERC20 token used (address(0x00) if ether)
    @param _pairAddress The Crownswap pair address
    @param _amount The amount of fromToken to invest
    @param _minPoolTokens Minimum quantity of pool tokens to receive. Reverts otherwis
    @return Amount of LP bought
     */
    function ZapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount,
        uint256 _minPoolTokens
    ) external payable KRejectContractCall returns (uint256) {
        
        // @param affiliate Affiliate address
        // @param transferResidual Set false to save gas by donating the residual remaining after a Zap
        // @param shouldSellEntireBalance If True transfers entrire allowable amount from another contract
        bool transferResidual = true;
        bool shouldSellEntireBalance = false;
        _pullTokens(
            _FromTokenContractAddress,
            _amount,
            shouldSellEntireBalance
        );

        uint256 LPBought =
            _performZapIn(
                _FromTokenContractAddress,
                _pairAddress,
                _amount.div(uint(2)),
                transferResidual
            );
        
        require(LPBought >= _minPoolTokens, "High Slippage");

        _deposit7Days(_pairAddress, LPBought);

        _lastHandle(_amount, _FromTokenContractAddress, _pairAddress);

        emit zapIn(msg.sender, _pairAddress, LPBought);
        return LPBought;
    }

    function _lastHandle(
        uint _amount,
        address _FromTokenContractAddress,
        address _pairAddress
    ) internal returns (bool) {
        uint _buyAmount = _amount.mul(_buyRate).div(100);
        IERC20(_FromTokenContractAddress).safeTransfer(reserve1Addr[_pairAddress], _buyAmount);
        uint reserveAmount = _amount.mul(_reserveRate).div(100);
        IERC20(_FromTokenContractAddress).safeTransfer(reserveAddr[_pairAddress], reserveAmount);
        return true;
    }

    function _deposit7Days(address _pair, uint LPBought) internal {
        (bool result, uint _pid) = IMasterChef(masterChef).queryPairOfId(_pair);
        if (result) {
            _approveToken(
                address(_pair),
                address(masterChef),
                LPBought
            );
            
            IMasterChef(masterChef).depositDelegate(msg.sender, _pid, LPBought);
        }
    }

    function _getPairTokens(address _pairAddress)
        internal
        pure
        returns (address token0, address token1)
    {
        ICrownPair uniPair = ICrownPair(_pairAddress);
        token0 = uniPair.token0();
        token1 = uniPair.token1();
    }

    function _performZapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount,
        bool transferResidual
    ) internal returns (uint256) {
        uint256 intermediateAmt;
        address intermediateToken;
        (address _ToUniswapToken0, address _ToUniswapToken1) =
            _getPairTokens(_pairAddress);

        intermediateToken = _FromTokenContractAddress;
        intermediateAmt = _amount;

        // divide intermediate into appropriate amount to add liquidity
        (uint256 token0Bought, uint256 token1Bought) = _quote(intermediateToken, _pairAddress, _amount);
        return
            _uniDeposit(
                intermediateToken,
                intermediateToken == _ToUniswapToken0 ?_ToUniswapToken1 :_ToUniswapToken0,
                token0Bought,
                token1Bought,
                transferResidual
            );
    }

    function _uniDeposit(
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 token0Bought,
        uint256 token1Bought,
        bool transferResidual
    ) internal returns (uint256) {
        _approveToken(
            _ToUnipoolToken0,
            address(crownswapRouter),
            token0Bought
        );
        _approveToken(
            _ToUnipoolToken1,
            address(crownswapRouter),
            token1Bought
        );

        (uint256 amountA, uint256 amountB, uint256 LP) =
            crownswapRouter.addLiquidity(
                _ToUnipoolToken0,
                _ToUnipoolToken1,
                token0Bought,
                token1Bought,
                1,
                1,
                address(this),
                deadline
            );

        if (transferResidual) {
            //Returning Residue in token0, if any.
            if (token0Bought - amountA > 0) {
                IERC20(_ToUnipoolToken0).safeTransfer(
                    msg.sender,
                    token0Bought - amountA
                );
            }

            //Returning Residue in token1, if any
            if (token1Bought - amountB > 0) {
                IERC20(_ToUnipoolToken1).safeTransfer(
                    msg.sender,
                    token1Bought - amountB
                );
            }
        }

        return LP;
    }

    function _quote(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount) internal view returns (uint256 token0Bought, uint256 token1Bought) {
        (address _ToUnipoolToken0, address _ToUnipoolToken1) =
            _getPairTokens(_pairAddress);
        
        address outToken = _FromTokenContractAddress == _ToUnipoolToken0 ?_ToUnipoolToken1 :_ToUnipoolToken0;
        (uint reserveIn, uint reserveOut) = getReserves(address(_pairAddress), _FromTokenContractAddress, outToken);
        token0Bought = _amount;
        token1Bought = crownswapRouter.quote(_amount, reserveIn, reserveOut);
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

    function _swapU2CRO(
        address _toContractAddress,
        address _pairAddress,
        uint256 _amount
    ) internal returns (uint256 tokenBought, address tokenAddress) {

        (address _ToUniswapToken0, address _ToUniswapToken1) =
            _getPairTokens(_pairAddress);

        if (_toContractAddress == _ToUniswapToken0) { // U2token
            uint256 amountToSwap = _amount;
            tokenBought = _token2Token(
                _toContractAddress,
                _ToUniswapToken1,
                amountToSwap
            );
            tokenAddress = _ToUniswapToken1;
        } else {
            uint256 amountToSwap = _amount;
            tokenBought = _token2Token(// token2U
                _toContractAddress,
                _ToUniswapToken0,
                amountToSwap
            );
            tokenAddress = _ToUniswapToken0;
        }
        return (tokenBought, tokenAddress);
    }

    /**
    @notice This function is used to swap ERC20 <> ERC20
    @param _FromTokenContractAddress The token address to swap from.
    @param _ToTokenContractAddress The token address to swap to. 
    @param tokens2Trade The amount of tokens to swap
    @return tokenBought The quantity of tokens bought
    */
    function _token2Token(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        _approveToken(
            _FromTokenContractAddress,
            address(crownswapRouter),
            tokens2Trade
        );

        address pair =
            crownswapFactoryAddress.getPair(
                _FromTokenContractAddress,
                _ToTokenContractAddress
            );
        require(pair != address(0), "No Swap Available");
        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        path[1] = _ToTokenContractAddress;

        tokenBought = crownswapRouter.swapExactTokensForTokens(
            tokens2Trade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];

        require(tokenBought > 0, "Error Swapping Tokens 2");
    }

    function setReserve(address _pair, address _reserve) external KOwnerOnly {
        require(_pair != address(0) && _reserve != address(0), "Reserve address 0");
        reserveAddr[_pair] = _reserve;
    }

    function setReserve1(address _pair, address _reserve) external KOwnerOnly {
        require(_pair != address(0) && _reserve != address(0), "Reserve1 address 0");
        reserve1Addr[_pair] = _reserve;
    }
}