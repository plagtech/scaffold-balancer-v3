// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @notice Minimal interface for Spraay Protocol's batch distribution contract.
/// @dev Spraay (https://spraay.app) enables push-model token distribution to up to 200 recipients
/// in a single transaction. Verified deployments (exact match on Sourcify):
///   - BNB Chain: 0x3093a2951FB77b3beDfB8BA20De645F7413432C1
///   - Base:      0x1646452F98E36A3c9Cfc3eDD8868221E207B5eEC
///
/// The protocol fee (`feeBps`, currently 30 bps) is charged on top of the distributed amount:
/// the caller must provide `totalAmount + totalAmount * feeBps / 10_000`.
interface ISpraay {
    struct Recipient {
        address payable recipient;
        uint256 amount;
    }

    /// @notice Batch-send native currency with per-recipient amounts. Excess msg.value is refunded.
    function sprayETH(Recipient[] calldata recipients) external payable;

    /// @notice Batch-send an ERC-20 with per-recipient amounts. Pulls `totalAmount + fee` from the caller.
    function sprayToken(address token, Recipient[] calldata recipients) external;

    /// @notice Batch-send the same amount to every recipient. `token == address(0)` means native currency.
    function sprayEqual(address token, address payable[] calldata recipients, uint256 amountPerRecipient)
        external
        payable;

    /// @notice Total cost (amount + protocol fee) the caller must provide to distribute `totalAmount`.
    function calculateTotalCost(uint256 totalAmount) external view returns (uint256);

    /// @notice Protocol fee in basis points (e.g. 30 = 0.30%).
    function feeBps() external view returns (uint256);

    /// @notice Maximum number of recipients per batch (currently 200).
    function MAX_RECIPIENTS() external view returns (uint256);
}
