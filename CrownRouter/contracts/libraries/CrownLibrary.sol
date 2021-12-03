pragma solidity =0.6.6;

import "./SafeMath.sol";
import "../interfaces/ICrownPair.sol";

library CrownLibrary {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CrownLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CrownLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'e4645d5a6b023515ad5a2a1dc5df27e82307af3af40c9c68e5a6e7a4bbd148cf' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        pairFor(factory, tokenA, tokenB);
        (uint reserve0, uint reserve1,) = ICrownPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // fetches and sorts the reserves for a pair
    function getSwapFee(address factory, address tokenA, address tokenB) internal view returns (uint swapFee, bool isBuy) {
        (swapFee, isBuy) = ICrownPair(pairFor(factory, tokenA, tokenB)).getSwapFee(tokenA);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'CrownLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CrownLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint swapFee, bool isBuy) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'CrownLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CrownLibrary: INSUFFICIENT_LIQUIDITY');
        if (isBuy) {
            uint amountInWithFee = amountIn.mul(uint(10000));
            uint numerator = amountInWithFee.mul(reserveOut);
            uint denominator = reserveIn.mul(uint(10000)).add(amountInWithFee);
            amountOut = (numerator / denominator);
            amountOut = amountOut.sub(amountOut.mul(swapFee)/10000);
        } else {
            uint amountInWithFee = amountIn.mul(9475);
            uint numerator = amountInWithFee.mul(reserveOut);
            uint denominator = reserveIn.mul(10000).add(amountInWithFee);
            amountOut = numerator / denominator;
        }
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint swapFee, bool isBuy) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'CrownLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CrownLibrary: INSUFFICIENT_LIQUIDITY');
        if (isBuy) {
            uint numerator = reserveIn.mul(amountOut).mul(10000);
            uint denominator = reserveOut.sub(amountOut).mul(10000-swapFee);
            amountIn = (numerator / denominator).add(1);
        } else {
            uint numerator = reserveIn.mul(amountOut).mul(9475);
            uint denominator = reserveOut.sub(amountOut).mul(10000);
            amountIn = (numerator / denominator).add(1);
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CrownLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            (uint fee, bool isBuy) = getSwapFee(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, fee, isBuy);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CrownLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            (uint fee, bool isBuy) = getSwapFee(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, fee, isBuy);
        }
    }
}