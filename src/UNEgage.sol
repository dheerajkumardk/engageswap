// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title UNEgage Token
 * @dev ERC20 token for EngageSwap rewards
 * Distributed as 1:1 ratio of USDC value equivalent based on swap fees
 */
contract UNEgage is ERC20, Ownable, ReentrancyGuard {
    // USDC token address (mainnet)
    address public constant USDC = 0xA0b86a33E6441b8C4C8C8C8C8C8C8C8C8C8C8C8C;
    
    // Minimum amount of tokens to mint (to avoid dust)
    uint256 public constant MIN_MINT_AMOUNT = 1e6; // 1 USDC worth
    
    // Total fees collected in USDC
    uint256 public totalFeesCollected;
    
    // Mapping to track user's earned rewards
    mapping(address => uint256) public earnedRewards;
    
    // Events
    event RewardsEarned(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event FeesCollected(uint256 amount);
    
    constructor() ERC20("UNEgage", "UNEG") Ownable(msg.sender) {
        // Initial supply can be minted by owner for initial distribution
    }
    
    /**
     * @dev Mint tokens to reward users based on their swap activity
     * @param user Address of the user to reward
     * @param usdcAmount Amount of USDC equivalent to reward
     */
    function mintRewards(address user, uint256 usdcAmount) external onlyOwner nonReentrant {
        require(user != address(0), "Invalid user address");
        require(usdcAmount > 0, "Amount must be greater than 0");
        
        // Convert USDC amount to UNEgage tokens (1:1 ratio)
        uint256 tokenAmount = usdcAmount;
        
        // Add to user's earned rewards
        earnedRewards[user] += tokenAmount;
        
        emit RewardsEarned(user, tokenAmount);
    }
    
    /**
     * @dev Allow users to claim their earned rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = earnedRewards[msg.sender];
        require(amount > 0, "No rewards to claim");
        
        // Reset earned rewards
        earnedRewards[msg.sender] = 0;
        
        // Mint tokens to user
        _mint(msg.sender, amount);
        
        emit RewardsClaimed(msg.sender, amount);
    }
    
    /**
     * @dev Get user's claimable rewards
     * @param user Address of the user
     * @return Amount of claimable rewards
     */
    function getClaimableRewards(address user) external view returns (uint256) {
        return earnedRewards[user];
    }
    
    /**
     * @dev Update total fees collected (called by hook)
     * @param amount Amount of fees collected
     */
    function updateFeesCollected(uint256 amount) external onlyOwner {
        totalFeesCollected += amount;
        emit FeesCollected(amount);
    }
    
    
    /**
     * @dev Override decimals to match USDC (6 decimals)
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
} 