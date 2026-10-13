//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelpers, CustomPoolConfig, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { ConstantProductFactory } from "../contracts/factories/ConstantProductFactory.sol";
import { BatchDistributeHook } from "../contracts/hooks/BatchDistributeHook.sol";
import { MockSpraay } from "../contracts/mocks/MockSpraay.sol";

/**
 * @title Deploy Batch Distribute Pool
 * @notice Deploys a constant product pool with a BatchDistributeHook that enables push-model
 *         token distribution (rewards, incentives, airdrops) to up to 200 recipients in a
 *         single transaction, powered by Spraay Protocol (https://spraay.app).
 * @dev For local development, a MockSpraay is deployed. For production deployments, replace
 *      `address(mockSpraay)` with the real Spraay contract address for your chain:
 *        - BNB Chain: 0x3093a2951FB77b3beDfB8BA20De645F7413432C1
 *        - Base:      0x1646452F98E36A3c9Cfc3eDD8868221E207B5eEC
 */
contract DeployBatchDistributePool is PoolHelpers, ScaffoldHelpers {
    function deployBatchDistributePool(address token1, address token2) internal {
        // Set the deployment configurations
        CustomPoolConfig memory poolConfig = getBatchDistributePoolConfig(token1, token2);
        InitializationConfig memory initConfig = getBatchDistributePoolInitConfig(token1, token2);

        // Start creating the transactions
        uint256 deployerPrivateKey = getDeployerPrivateKey();
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        // Deploy a factory (reuses the constant product factory — any Balancer v3 factory works)
        ConstantProductFactory factory = new ConstantProductFactory(vault, 365 days);
        console.log("BatchDistribute Factory deployed at: %s", address(factory));

        // Deploy a mock Spraay contract for local development
        MockSpraay mockSpraay = new MockSpraay();
        console.log("MockSpraay deployed at: %s", address(mockSpraay));

        // Deploy the BatchDistributeHook
        // The deployer is both the hook owner and the initial distribution operator
        BatchDistributeHook batchDistributeHook = new BatchDistributeHook(
            IVault(address(vault)),
            address(mockSpraay),
            deployer, // owner
            deployer // initial operator
        );
        console.log("BatchDistributeHook deployed at: %s", address(batchDistributeHook));

        // Deploy a pool and register it with the vault
        address pool = factory.create(
            poolConfig.name,
            poolConfig.symbol,
            poolConfig.salt,
            poolConfig.tokenConfigs,
            poolConfig.swapFeePercentage,
            poolConfig.protocolFeeExempt,
            poolConfig.roleAccounts,
            address(batchDistributeHook), // poolHooksContract
            poolConfig.liquidityManagement
        );
        console.log("Batch Distribute Pool deployed at: %s", pool);

        // Approve the router to spend tokens for pool initialization
        approveRouterWithPermit2(initConfig.tokens);

        // Seed the pool with initial liquidity using Router as entrypoint
        router.initialize(
            pool,
            initConfig.tokens,
            initConfig.exactAmountsIn,
            initConfig.minBptAmountOut,
            initConfig.wethIsEth,
            initConfig.userData
        );
        console.log("Batch Distribute Pool initialized successfully!");
        vm.stopBroadcast();
    }

    /**
     * @dev Set all of the configurations for deploying and registering a pool here
     */
    function getBatchDistributePoolConfig(
        address token1,
        address token2
    ) internal view returns (CustomPoolConfig memory config) {
        string memory name = "Batch Distribute Pool";
        string memory symbol = "BDP";
        bytes32 salt = keccak256(abi.encode(block.number));
        uint256 swapFeePercentage = 0.01e18; // 1%
        bool protocolFeeExempt = false;
        address poolHooksContract = address(0); // set later during factory.create()

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        tokenConfigs[0] = TokenConfig({
            token: IERC20(token1),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokenConfigs[1] = TokenConfig({
            token: IERC20(token2),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: address(0),
            poolCreator: address(0)
        });
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: false,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false,
            enableDonation: false
        });

        config = CustomPoolConfig({
            name: name,
            symbol: symbol,
            salt: salt,
            tokenConfigs: sortTokenConfig(tokenConfigs),
            swapFeePercentage: swapFeePercentage,
            protocolFeeExempt: protocolFeeExempt,
            roleAccounts: roleAccounts,
            poolHooksContract: poolHooksContract,
            liquidityManagement: liquidityManagement
        });
    }

    /**
     * @dev Set the pool initialization configurations here
     */
    function getBatchDistributePoolInitConfig(
        address token1,
        address token2
    ) internal pure returns (InitializationConfig memory config) {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = 50e18;
        exactAmountsIn[1] = 50e18;
        uint256 minBptAmountOut = 49e18;
        bool wethIsEth = false;
        bytes memory userData = bytes("");

        config = InitializationConfig({
            tokens: InputHelpers.sortTokens(tokens),
            exactAmountsIn: exactAmountsIn,
            minBptAmountOut: minBptAmountOut,
            wethIsEth: wethIsEth,
            userData: userData
        });
    }
}
