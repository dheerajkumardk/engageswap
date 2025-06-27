// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/src/BaseHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title EngageSwapHook
 * @dev Hook contract for EngageSwap that charges an extra 0.01% fee and tracks rewards
 * Implements Uniswap V4 beforeSwap hook interface
 */
contract EngageSwapHook is BaseHook, ReentrancyGuard {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    
    // UNEgage token contract
    address public immutable unEgageToken;
    
    // USDC token address (mainnet)
    address public constant USDC = 0xA0b86a33E6441b8C4C8C8C8C8C8C8C8C8C8C8C8C;
    
    // Extra fee percentage (0.01% = 1 basis point)
    uint24 public constant EXTRA_FEE_BPS = 1; // 0.01%
    uint24 public constant EXTRA_FEE_DENOMINATOR = 10000; // 100%
    
    // Fee collection address
    address public feeCollector;
    
    // Mapping to track user's swap volume for rewards
    mapping(address => uint256) public userSwapVolume;
    
    // Total swap volume
    uint256 public totalSwapVolume;
    
    // Events
    event ExtraFeeCollected(address indexed user, Currency indexed currency, uint256 amount);
    event SwapVolumeTracked(address indexed user, uint256 volume);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    
    error InvalidFeeCollector();
    error InvalidTokenAddress();
    
    constructor(
        IPoolManager _poolManager,
        address _unEgageToken,
        address _feeCollector
    ) BaseHook(_poolManager) {
        if (_unEgageToken == address(0)) revert InvalidTokenAddress();
        if (_feeCollector == address(0)) revert InvalidFeeCollector();
        
        unEgageToken = _unEgageToken;
        feeCollector = _feeCollector;
    }
    
    /**
     * @dev Get the hook permissions required
     * This hook only needs beforeSwap permission
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }
    
    /**
     * @dev beforeSwap hook implementation
     * Charges an extra 0.01% fee and tracks swap volume for rewards
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4, BeforeSwapDelta, uint24) {
        // Calculate the extra fee amount
        uint256 extraFeeAmount = _calculateExtraFee(params.amountSpecified);
        
        // Determine which currency to charge the fee in
        Currency feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // Track swap volume for rewards (in USDC equivalent)
        _trackSwapVolume(sender, params.amountSpecified, key);
        
        // If there's an extra fee to collect
        if (extraFeeAmount > 0) {
            // Transfer the extra fee from the sender to this contract
            feeCurrency.transfer(sender, address(this), extraFeeAmount);
            
            // Transfer the fee to the fee collector
            feeCurrency.transfer(address(this), feeCollector, extraFeeAmount);
            
            emit ExtraFeeCollected(sender, feeCurrency, extraFeeAmount);
        }
        
        // Return the hook selector and no delta (we don't modify the swap)
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }
    
    /**
     * @dev Calculate the extra fee amount (0.01% of swap amount)
     * @param amountSpecified The swap amount
     * @return The extra fee amount
     */
    function _calculateExtraFee(int256 amountSpecified) internal pure returns (uint256) {
        if (amountSpecified <= 0) return 0;
        
        uint256 amount = uint256(amountSpecified);
        return (amount * EXTRA_FEE_BPS) / EXTRA_FEE_DENOMINATOR;
    }
    
    /**
     * @dev Track swap volume for reward calculations
     * @param user The user performing the swap
     * @param amountSpecified The swap amount
     * @param key The pool key
     */
    function _trackSwapVolume(address user, int256 amountSpecified, PoolKey calldata key) internal {
        if (amountSpecified <= 0) return;
        
        uint256 volume = uint256(amountSpecified);
        
        // For now, we'll track volume in the input currency
        // In a real implementation, you might want to convert to USDC equivalent
        userSwapVolume[user] += volume;
        totalSwapVolume += volume;
        
        emit SwapVolumeTracked(user, volume);
    }
    
    /**
     * @dev Calculate rewards for a user based on their swap volume
     * @param user The user address
     * @return The reward amount in USDC equivalent
     */
    function calculateUserRewards(address user) external view returns (uint256) {
        uint256 userVolume = userSwapVolume[user];
        if (userVolume == 0 || totalSwapVolume == 0) return 0;
        
        // Calculate reward as a proportion of total fees collected
        // This is a simplified calculation - you might want to implement a more sophisticated reward mechanism
        uint256 totalFees = _getTotalFeesCollected();
        return (userVolume * totalFees) / totalSwapVolume;
    }
    
    /**
     * @dev Get total fees collected (placeholder - implement based on your fee collection mechanism)
     * @return Total fees collected
     */
    function _getTotalFeesCollected() internal view returns (uint256) {
        // This should be implemented based on how you track fees
        // For now, returning a placeholder
        return 0;
    }
    
    /**
     * @dev Update fee collector address (only owner)
     * @param newFeeCollector New fee collector address
     */
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) revert InvalidFeeCollector();
        
        address oldCollector = feeCollector;
        feeCollector = newFeeCollector;
        
        emit FeeCollectorUpdated(oldCollector, newFeeCollector);
    }
    
    /**
     * @dev Get user's swap volume
     * @param user The user address
     * @return The user's total swap volume
     */
    function getUserSwapVolume(address user) external view returns (uint256) {
        return userSwapVolume[user];
    }
    
} 