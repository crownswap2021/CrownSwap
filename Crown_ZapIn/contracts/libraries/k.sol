// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.4;

contract KOwnerable {

    address internal _authAddress;
    bool private _call_locked;

    constructor() public {
        _authAddress = msg.sender;
    }

    modifier KOwnerOnly() {
        require(msg.sender == _authAddress, 'NotAuther');
        _;
    }

    modifier KRejectContractCall() {
        uint256 size;
        address payable safeAddr = payable(msg.sender);
        assembly {size := extcodesize(safeAddr)}
        require( size == 0, "Sender Is Contract" );
        _;
    }

    modifier KDAODefense() {
        require(!_call_locked, "DAO_Warning");
        _call_locked = true;
        _;
        _call_locked = false;
    }

    function timestempZero() internal view returns (uint) {
        return timestemp() / 1 days * 1 days;
    }

    function timestemp() internal view returns (uint) {
        return block.timestamp;
    }
}
