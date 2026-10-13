// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISpraay } from "../interfaces/ISpraay.sol";

/// @notice Minimal mock of Spraay's batch distribution contract, for use in scaffold tests.
/// @dev Implements the full ERC-20 pull-and-distribute flow so that token balance assertions
/// in tests reflect the same behaviour as the real Spraay contract on-chain.
contract MockSpraay is ISpraay {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_BPS = 30;

    /// @inheritdoc ISpraay
    function sprayETH(Recipient[] calldata recipients) external payable override {
        uint256 totalAmount;
        for (uint256 i; i < recipients.length; ++i) {
            totalAmount += recipients[i].amount;
        }
        uint256 required = calculateTotalCost(totalAmount);
        require(msg.value >= required, "MockSpraay: insufficient value");

        for (uint256 i; i < recipients.length; ++i) {
            (bool ok, ) = recipients[i].recipient.call{value: recipients[i].amount}("");
            require(ok, "MockSpraay: ETH transfer failed");
        }

        uint256 excess = msg.value - required;
        if (excess > 0) {
            (bool ok, ) = msg.sender.call{value: excess}("");
            require(ok, "MockSpraay: refund failed");
        }
    }

    /// @inheritdoc ISpraay
    function sprayToken(address token, Recipient[] calldata recipients) external override {
        uint256 totalAmount;
        for (uint256 i; i < recipients.length; ++i) {
            totalAmount += recipients[i].amount;
        }
        uint256 totalCost = calculateTotalCost(totalAmount);

        // Pull totalCost from the caller (the hook)
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalCost);

        // Distribute to each recipient
        for (uint256 i; i < recipients.length; ++i) {
            IERC20(token).safeTransfer(recipients[i].recipient, recipients[i].amount);
        }
        // Fee stays in the mock contract
    }

    /// @inheritdoc ISpraay
    function sprayEqual(
        address token,
        address payable[] calldata recipients,
        uint256 amountPerRecipient
    ) external payable override {
        uint256 totalAmount = amountPerRecipient * recipients.length;
        uint256 totalCost = calculateTotalCost(totalAmount);

        if (token == address(0)) {
            require(msg.value >= totalCost, "MockSpraay: insufficient value");
            for (uint256 i; i < recipients.length; ++i) {
                (bool ok, ) = recipients[i].call{value: amountPerRecipient}("");
                require(ok, "MockSpraay: ETH transfer failed");
            }
            uint256 excess = msg.value - totalCost;
            if (excess > 0) {
                (bool ok, ) = msg.sender.call{value: excess}("");
                require(ok, "MockSpraay: refund failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalCost);
            for (uint256 i; i < recipients.length; ++i) {
                IERC20(token).safeTransfer(recipients[i], amountPerRecipient);
            }
        }
    }

    /// @inheritdoc ISpraay
    function calculateTotalCost(uint256 totalAmount) public pure override returns (uint256) {
        return totalAmount + (totalAmount * FEE_BPS) / 10_000;
    }

    /// @inheritdoc ISpraay
    function feeBps() external pure override returns (uint256) {
        return FEE_BPS;
    }

    /// @inheritdoc ISpraay
    function MAX_RECIPIENTS() external pure override returns (uint256) {
        return 200;
    }

    receive() external payable {}
}
