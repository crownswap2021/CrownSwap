// SPDX-License-Identifier: GPL-2.0

pragma solidity 0.8.4;
import "./ZapBaseV2.sol";

abstract contract ZapInBaseV3 is ZapBaseV2 {
    using SafeERC20 for IERC20;

    function _pullTokens(
        address token,
        uint256 amount,
        bool shouldSellEntireBalance
    ) internal returns (uint256 value) {
        require(amount > 0, "Invalid token amount");
        require(msg.value == 0, "Eth sent with token");

        //transfer token
        if (shouldSellEntireBalance) {
            require(
                Address.isContract(msg.sender),
                "ERR: shouldSellEntireBalance is true for EOA"
            );
            amount = IERC20(token).allowance(msg.sender, address(this));
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        return amount;
    }
}