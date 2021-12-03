pragma solidity =0.5.16;

import './interfaces/ICrownFactory.sol';
import './CrownPair.sol';

contract CrownFactory is ICrownFactory {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(CrownPair).creationCode));

    address public feeTo;
    address public feeToSetter;
    mapping(address => address) internal reserve;
    mapping(address => address) internal pledge;
    mapping(address => address) internal burn;
    mapping(address => address) internal top100;
    mapping(address => address) internal visit;
    mapping(address => address) public targetAddress;
    mapping(address => address) public marketAddress;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor() public {
        feeToSetter = msg.sender;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Crown: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Crown: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Crown: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(CrownPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ICrownPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setBaseToken(address _pair, address token) external onlyFeeToSetter {
        require(_pair != address(0) && token != address(0));
        ICrownPair(_pair).setBaseToken(token);
    }

    function setReserve(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && reserve[_pair] == address(0));
        reserve[_pair] = _addr;
    }

    function getReserve(address _pair) external view returns (address) {
        return reserve[_pair];
    }

    function setMined(address _pair, bool _mined) external onlyFeeToSetter {
        require(_pair != address(0));
        ICrownPair(_pair).setMined(_mined);
    }

    function getMined(address _pair) external view returns (bool) {
        return ICrownPair(_pair).getMined();
    }

    function setPledge(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && pledge[_pair] == address(0));
        pledge[_pair] = _addr;
    }

    function getPledge(address _pair) external view returns (address) {
        return pledge[_pair];
    }

    function setBurn(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && burn[_pair] == address(0));
        burn[_pair] = _addr;
    }

    function getBurn(address _pair) external view returns (address) {
        return burn[_pair];
    }

    function setTop100(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && top100[_pair] == address(0));
        top100[_pair] = _addr;
    }

    function getTop100(address _pair) external view returns (address) {
        return top100[_pair];
    }

    function setVisit(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && visit[_pair] == address(0));
        visit[_pair] = _addr;
    }

    function getVisit(address _pair) external view returns (address) {
        return visit[_pair];
    }

    function setMarketAddress(address _pair, address _addr) external onlyFeeToSetter {
        require(_pair != address(0) && _addr != address(0) && marketAddress[_pair] == address(0));
        marketAddress[_pair] = _addr;
    }

    function getMarketAddress(address _pair) external view returns (address) {
        return marketAddress[_pair];
    }

    modifier onlyFeeToSetter() {
        require(msg.sender == feeToSetter, "Crown: FORBIDDEN");
        _;
    }
}
