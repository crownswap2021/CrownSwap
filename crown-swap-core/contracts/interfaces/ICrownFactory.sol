pragma solidity =0.5.16;

interface ICrownFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setBaseToken(address _pair, address token) external;
    function getReserve(address _pair) external view returns (address);
    function setReserve(address _pair, address _addr) external;
    function setMined(address _pair, bool _mined) external;
    function getMined(address _pair) external view returns (bool);
    function setPledge(address _pair, address _addr) external;
    function getPledge(address _pair) external view returns (address);
    function setBurn(address _pair, address _addr) external;
    function getBurn(address _pair) external view returns (address);
    function setTop100(address _pair, address _addr) external;
    function getTop100(address _pair) external view returns (address);
    function setVisit(address _pair, address _addr) external;
    function getVisit(address _pair) external view returns (address);
    function setMarketAddress(address _pair, address _addr) external;
    function getMarketAddress(address _pair) external view returns (address);
}
