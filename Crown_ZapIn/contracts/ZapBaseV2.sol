// SPDX-License-Identifier: GPL-2.0

pragma solidity 0.8.4;

import "./libraries/k.sol";
import "./SafeERC20.sol";

abstract contract ZapBaseV2 is KOwnerable {
    using SafeERC20 for IERC20;

    function _approveToken(address token, address spender) internal {
        IERC20 _token = IERC20(token);
        if (_token.allowance(address(this), spender) > 0) return;
        else {
            _token.safeApprove(spender, type(uint256).max);
        }
    }

    function _approveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeApprove(spender, amount);
    }

    receive() external payable {
        require(msg.sender != tx.origin, "Do not send ETH directly");
    }
}