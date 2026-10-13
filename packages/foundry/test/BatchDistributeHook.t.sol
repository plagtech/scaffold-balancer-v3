// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { BatchDistributeHook } from "../contracts/hooks/BatchDistributeHook.sol";
import { MockSpraay } from "../contracts/mocks/MockSpraay.sol";

/**
 * @notice Tests for BatchDistributeHook — a Spraay-powered push-distribution hook for Balancer v3.
 * @dev Uses MockSpraay to simulate the full pull-and-distribute ERC-20 flow without needing
 * a fork of the live Spraay contract.
 */
contract BatchDistributeHookTest is BaseVaultTest {
    using CastingHelpers for address[];

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    MockSpraay internal mockSpraay;

    function setUp() public override {
        super.setUp();
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        mockSpraay = new MockSpraay();

        // lp is both the hook owner and the initial distribution operator
        vm.prank(lp);
        BatchDistributeHook hook = new BatchDistributeHook(
            IVault(address(vault)),
            address(mockSpraay),
            lp, // owner
            lp // initial operator
        );
        vm.label(address(hook), "BatchDistributeHook");
        return address(hook);
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, label);

        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        vm.expectEmit();
        emit BatchDistributeHook.PoolRegistered(newPool);

        factoryMock.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    // ======================== Registration ========================

    function testPoolRegistration() public view {
        assertTrue(
            BatchDistributeHook(payable(poolHooksContract)).isRegisteredPool(pool),
            "Pool should be registered after _createPool"
        );
    }

    // ======================== Distribution ========================

    function testBatchDistribute() public {
        address r1 = makeAddr("recipient1");
        address r2 = makeAddr("recipient2");
        address r3 = makeAddr("recipient3");

        address[] memory recipients = new address[](3);
        recipients[0] = r1;
        recipients[1] = r2;
        recipients[2] = r3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        uint256 totalAmount = 600e18;
        uint256 totalCost = mockSpraay.calculateTotalCost(totalAmount); // 600 + 1.8 = 601.8e18

        // Fund operator and approve the hook to pull tokens
        deal(address(dai), lp, totalCost);
        vm.startPrank(lp);
        dai.approve(address(poolHooksContract), totalCost);

        // Expect the BatchDistributed event
        vm.expectEmit(true, true, true, true);
        emit BatchDistributeHook.BatchDistributed(
            pool, lp, address(dai), 3, totalAmount, totalCost - totalAmount
        );

        BatchDistributeHook(payable(poolHooksContract)).batchDistribute(
            pool,
            address(dai),
            recipients,
            amounts
        );
        vm.stopPrank();

        // Each recipient receives exactly the specified amount
        assertEq(dai.balanceOf(r1), 100e18, "Recipient 1 balance wrong");
        assertEq(dai.balanceOf(r2), 200e18, "Recipient 2 balance wrong");
        assertEq(dai.balanceOf(r3), 300e18, "Recipient 3 balance wrong");

        // The hook should hold zero tokens after the distribution
        assertEq(dai.balanceOf(poolHooksContract), 0, "Hook should not hold tokens");
    }

    function testBatchDistributeEqual() public {
        address r1 = makeAddr("recipient1");
        address r2 = makeAddr("recipient2");

        address[] memory recipients = new address[](2);
        recipients[0] = r1;
        recipients[1] = r2;

        uint256 amountEach = 500e18;
        uint256 totalAmount = amountEach * recipients.length;
        uint256 totalCost = mockSpraay.calculateTotalCost(totalAmount);

        deal(address(dai), lp, totalCost);
        vm.startPrank(lp);
        dai.approve(address(poolHooksContract), totalCost);

        BatchDistributeHook(payable(poolHooksContract)).batchDistributeEqual(
            pool,
            address(dai),
            recipients,
            amountEach
        );
        vm.stopPrank();

        assertEq(dai.balanceOf(r1), amountEach, "Recipient 1 balance wrong");
        assertEq(dai.balanceOf(r2), amountEach, "Recipient 2 balance wrong");
        assertEq(dai.balanceOf(poolHooksContract), 0, "Hook should not hold tokens");
    }

    // ======================== Access control ========================

    function testOnlyOperatorCanDistribute() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // bob is not an operator
        vm.expectRevert(BatchDistributeHook.NotOperator.selector);
        vm.prank(bob);
        BatchDistributeHook(payable(poolHooksContract)).batchDistribute(
            pool,
            address(dai),
            recipients,
            amounts
        );
    }

    function testUnregisteredPoolReverts() public {
        address fakePool = makeAddr("fakePool");

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.expectRevert(BatchDistributeHook.PoolNotRegistered.selector);
        vm.prank(lp);
        BatchDistributeHook(payable(poolHooksContract)).batchDistribute(
            fakePool,
            address(dai),
            recipients,
            amounts
        );
    }

    // ======================== Admin ========================

    function testSetOperator() public {
        BatchDistributeHook hook = BatchDistributeHook(payable(poolHooksContract));

        assertFalse(hook.isOperator(bob), "Bob should not be operator initially");

        vm.prank(lp);
        hook.setOperator(bob, true);
        assertTrue(hook.isOperator(bob), "Bob should be operator after being added");

        vm.prank(lp);
        hook.setOperator(bob, false);
        assertFalse(hook.isOperator(bob), "Bob should not be operator after being removed");
    }
}
