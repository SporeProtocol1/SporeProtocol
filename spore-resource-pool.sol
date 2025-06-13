// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGrowthTracker.sol";

/**
 * @title ResourcePool
 * @author Spore Protocol
 * @notice Manages shared resources (water, nutrients, light) across multiple organisms
 * @dev Implements dynamic resource allocation with priority queuing
 */
contract ResourcePool is AccessControl, ReentrancyGuard {
    using Math for uint256;
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOURCE_MANAGER_ROLE = keccak256("RESOURCE_MANAGER_ROLE");
    
    // Resource types
    bytes32 public constant WATER = keccak256("WATER");
    bytes32 public constant NITROGEN = keccak256("NITROGEN");
    bytes32 public constant PHOSPHORUS = keccak256("PHOSPHORUS");
    bytes32 public constant POTASSIUM = keccak256("POTASSIUM");
    bytes32 public constant LIGHT = keccak256("LIGHT");
    bytes32 public constant CO2 = keccak256("CO2");
    
    struct Resource {
        uint256 totalCapacity;      // Maximum resource capacity
        uint256 currentAmount;      // Currently available
        uint256 replenishRate;      // Units per block
        uint256 lastReplenishBlock; // Last replenishment
        uint256 minAllocation;      // Minimum allocation per organism
        uint256 maxAllocation;      // Maximum allocation per organism
        bool isActive;
    }
    
    struct Allocation {
        uint256 amount;
        uint256 priority;          // 0-100, higher gets preference
        uint256 lastClaimBlock;
        uint256 accumulatedUnused; // Track unused allocations
        bool isActive;
    }
    
    struct AllocationRequest {
        uint256 organismId;
        bytes32 resourceType;
        uint256 amount;
        uint256 priority;
    }
    
    // Storage
    mapping(bytes32 => Resource) public resources;
    mapping(uint256 => mapping(bytes32 => Allocation)) public allocations;
    mapping(bytes32 => uint256) public totalAllocated;
    mapping(uint256 => uint256) public organismResourceScore; // Performance tracking
    
    // Queuing system for fair distribution
    mapping(bytes32 => uint256[]) public waitingQueue;
    mapping(bytes32 => mapping(uint256 => bool)) public inQueue;
    
    IGrowthTracker public immutable growthTracker;
    
    // Events
    event ResourceInitialized(bytes32 indexed resourceType, uint256 capacity, uint256 replenishRate);
    event ResourceAllocated(uint256 indexed organismId, bytes32 indexed resourceType, uint256 amount);
    event ResourceClaimed(uint256 indexed organismId, bytes32 indexed resourceType, uint256 amount);
    event ResourceReleased(uint256 indexed organismId, bytes32 indexed resourceType, uint256 amount);
    event ResourceReplenished(bytes32 indexed resourceType, uint256 amount);
    event AllocationPriorityUpdated(uint256 indexed organismId, bytes32 indexed resourceType, uint256 priority);
    
    // Errors
    error ResourceNotActive();
    error InsufficientResources(uint256 requested, uint256 available);
    error AllocationOutOfBounds(uint256 requested, uint256 min, uint256 max);
    error OrganismNotActive();
    error AllocationNotActive();
    error AlreadyInQueue();
    
    constructor(address _growthTracker) {
        require(_growthTracker != address(0), "Invalid growth tracker");
        growthTracker = IGrowthTracker(_growthTracker);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(RESOURCE_MANAGER_ROLE, msg.sender);
        
        // Initialize default resources
        _initializeDefaultResources();
    }
    
    /**
     * @notice Initializes a new resource type
     * @param resourceType Resource identifier
     * @param capacity Maximum capacity
     * @param replenishRate Units replenished per block
     * @param minAllocation Minimum allocation per organism
     * @param maxAllocation Maximum allocation per organism
     */
    function initializeResource(
        bytes32 resourceType,
        uint256 capacity,
        uint256 replenishRate,
        uint256 minAllocation,
        uint256 maxAllocation
    ) external onlyRole(RESOURCE_MANAGER_ROLE) {
        require(capacity > 0, "Invalid capacity");
        require(maxAllocation >= minAllocation, "Invalid allocation bounds");
        
        resources[resourceType] = Resource({
            totalCapacity: capacity,
            currentAmount: capacity,
            replenishRate: replenishRate,
            lastReplenishBlock: block.number,
            minAllocation: minAllocation,
            maxAllocation: maxAllocation,
            isActive: true
        });
        
        emit ResourceInitialized(resourceType, capacity, replenishRate);
    }
    
    /**
     * @notice Allocates resources to an organism
     * @param organismId The organism requesting resources
     * @param resourceType Type of resource
     * @param amount Amount requested
     * @param priority Priority level (0-100)
     */
    function allocateResource(
        uint256 organismId,
        bytes32 resourceType,
        uint256 amount,
        uint256 priority
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Resource storage resource = resources[resourceType];
        if (!resource.isActive) revert ResourceNotActive();
        
        // Verify organism is active
        (, , , , uint16 healthScore, , bool isActive) = growthTracker.organisms(organismId);
        if (!isActive) revert OrganismNotActive();
        
        // Validate allocation bounds
        if (amount < resource.minAllocation || amount > resource.maxAllocation) {
            revert AllocationOutOfBounds(amount, resource.minAllocation, resource.maxAllocation);
        }
        
        // Replenish resources first
        _replenishResource(resourceType);
        
        // Check if immediate allocation is possible
        uint256 availableAmount = resource.currentAmount - totalAllocated[resourceType];
        
        if (amount <= availableAmount) {
            // Immediate allocation
            _performAllocation(organismId, resourceType, amount, priority);
        } else {
            // Add to waiting queue
            _addToQueue(organismId, resourceType, amount, priority);
        }
    }
    
    /**
     * @notice Claims allocated resources
     * @param organismId The organism claiming resources
     * @param resourceType Type of resource to claim
     * @return claimedAmount Amount actually claimed
     */
    function claimResource(
        uint256 organismId,
        bytes32 resourceType
    ) external nonReentrant returns (uint256 claimedAmount) {
        Allocation storage allocation = allocations[organismId][resourceType];
        if (!allocation.isActive) revert AllocationNotActive();
        
        // Calculate claimable amount based on time passed
        uint256 blocksSinceLastClaim = block.number - allocation.lastClaimBlock;
        claimedAmount = Math.min(
            allocation.amount * blocksSinceLastClaim / 100, // 1% per block
            allocation.amount
        );
        
        allocation.lastClaimBlock = block.number;
        
        // Update organism resource score for performance tracking
        organismResourceScore[organismId] += claimedAmount;
        
        emit ResourceClaimed(organismId, resourceType, claimedAmount);
    }
    
    /**
     * @notice Releases unused resources back to the pool
     * @param organismId The organism releasing resources
     * @param resourceType Type of resource
     * @param amount Amount to release
     */
    function releaseResource(
        uint256 organismId,
        bytes32 resourceType,
        uint256 amount
    ) external {
        Allocation storage allocation = allocations[organismId][resourceType];
        require(allocation.isActive, "No active allocation");
        require(allocation.amount >= amount, "Insufficient allocation");
        
        allocation.amount -= amount;
        totalAllocated[resourceType] -= amount;
        
        // Process waiting queue if resources became available
        _processQueue(resourceType);
        
        emit ResourceReleased(organismId, resourceType, amount);
    }
    
    /**
     * @notice Batch allocates resources for multiple organisms
     * @param requests Array of allocation requests
     */
    function batchAllocate(AllocationRequest[] calldata requests) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < requests.length; i++) {
            allocateResource(
                requests[i].organismId,
                requests[i].resourceType,
                requests[i].amount,
                requests[i].priority
            );
        }
    }
    
    /**
     * @notice Optimizes resource distribution based on organism health and growth stage
     * @param resourceType Resource to optimize
     * @param organismIds Array of organism IDs to consider
     */
    function optimizeDistribution(
        bytes32 resourceType,
        uint256[] calldata organismIds
    ) external onlyRole(RESOURCE_MANAGER_ROLE) {
        _replenishResource(resourceType);
        
        // Calculate optimal distribution based on organism metrics
        uint256 totalHealthScore = 0;
        uint256[] memory healthScores = new uint256[](organismIds.length);
        
        for (uint256 i = 0; i < organismIds.length; i++) {
            (, , , , uint16 healthScore, , bool isActive) = growthTracker.organisms(organismIds[i]);
            if (isActive) {
                healthScores[i] = healthScore;
                totalHealthScore += healthScore;
            }
        }
        
        // Redistribute based on health scores
        Resource storage resource = resources[resourceType];
        uint256 availableForRedistribution = resource.currentAmount;
        
        for (uint256 i = 0; i < organismIds.length; i++) {
            if (healthScores[i] > 0) {
                uint256 newAllocation = (availableForRedistribution * healthScores[i]) / totalHealthScore;
                newAllocation = Math.min(newAllocation, resource.maxAllocation);
                newAllocation = Math.max(newAllocation, resource.minAllocation);
                
                allocations[organismIds[i]][resourceType] = Allocation({
                    amount: newAllocation,
                    priority: (healthScores[i] * 100) / 10000, // Convert to 0-100 scale
                    lastClaimBlock: block.number,
                    accumulatedUnused: 0,
                    isActive: true
                });
            }
        }
    }
    
    /**
     * @notice Gets current resource availability
     * @param resourceType Resource to query
     * @return available Amount available for allocation
     * @return capacity Total capacity
     * @return allocated Currently allocated amount
     */
    function getResourceAvailability(bytes32 resourceType) external view returns (
        uint256 available,
        uint256 capacity,
        uint256 allocated
    ) {
        Resource memory resource = resources[resourceType];
        
        // Calculate replenished amount
        uint256 blocksPassed = block.number - resource.lastReplenishBlock;
        uint256 replenished = blocksPassed * resource.replenishRate;
        uint256 currentTotal = Math.min(
            resource.currentAmount + replenished,
            resource.totalCapacity
        );
        
        capacity = resource.totalCapacity;
        allocated = totalAllocated[resourceType];
        available = currentTotal > allocated ? currentTotal - allocated : 0;
    }
    
    /**
     * @notice Gets allocation details for an organism
     * @param organismId Organism to query
     * @param resourceType Resource type
     * @return amount Allocated amount
     * @return priority Allocation priority
     * @return utilizationRate Percentage of allocation being used
     */
    function getAllocationDetails(
        uint256 organismId,
        bytes32 resourceType
    ) external view returns (
        uint256 amount,
        uint256 priority,
        uint256 utilizationRate
    ) {
        Allocation memory allocation = allocations[organismId][resourceType];
        amount = allocation.amount;
        priority = allocation.priority;
        
        if (allocation.amount > 0) {
            utilizationRate = 100 - ((allocation.accumulatedUnused * 100) / allocation.amount);
        }
    }
    
    // Internal functions
    
    function _initializeDefaultResources() private {
        // Water - high capacity, moderate replenish
        _initializeResource(WATER, 1000000, 100, 10, 1000);
        
        // Nutrients - lower capacity, slow replenish
        _initializeResource(NITROGEN, 500000, 50, 5, 500);
        _initializeResource(PHOSPHORUS, 300000, 30, 3, 300);
        _initializeResource(POTASSIUM, 400000, 40, 4, 400);
        
        // Light - fixed capacity, instant replenish
        _initializeResource(LIGHT, 100000, 100000, 10, 1000);
        
        // CO2 - high capacity, fast replenish
        _initializeResource(CO2, 800000, 200, 8, 800);
    }
    
    function _initializeResource(
        bytes32 resourceType,
        uint256 capacity,
        uint256 replenishRate,
        uint256 minAllocation,
        uint256 maxAllocation
    ) private {
        resources[resourceType] = Resource({
            totalCapacity: capacity,
            currentAmount: capacity,
            replenishRate: replenishRate,
            lastReplenishBlock: block.number,
            minAllocation: minAllocation,
            maxAllocation: maxAllocation,
            isActive: true
        });
    }
    
    function _replenishResource(bytes32 resourceType) private {
        Resource storage resource = resources[resourceType];
        
        uint256 blocksPassed = block.number - resource.lastReplenishBlock;
        if (blocksPassed > 0) {
            uint256 replenishAmount = blocksPassed * resource.replenishRate;
            uint256 newAmount = Math.min(
                resource.currentAmount + replenishAmount,
                resource.totalCapacity
            );
            
            if (newAmount > resource.currentAmount) {
                emit ResourceReplenished(resourceType, newAmount - resource.currentAmount);
            }
            
            resource.currentAmount = newAmount;
            resource.lastReplenishBlock = block.number;
        }
    }
    
    function _performAllocation(
        uint256 organismId,
        bytes32 resourceType,
        uint256 amount,
        uint256 priority
    ) private {
        allocations[organismId][resourceType] = Allocation({
            amount: amount,
            priority: priority,
            lastClaimBlock: block.number,
            accumulatedUnused: 0,
            isActive: true
        });
        
        totalAllocated[resourceType] += amount;
        
        emit ResourceAllocated(organismId, resourceType, amount);
    }
    
    function _addToQueue(
        uint256 organismId,
        bytes32 resourceType,
        uint256 amount,
        uint256 priority
    ) private {
        if (inQueue[resourceType][organismId]) revert AlreadyInQueue();
        
        waitingQueue[resourceType].push(organismId);
        inQueue[resourceType][organismId] = true;
        
        // Store pending allocation
        allocations[organismId][resourceType] = Allocation({
            amount: amount,
            priority: priority,
            lastClaimBlock: 0, // Not claimable yet
            accumulatedUnused: 0,
            isActive: false // Pending
        });
    }
    
    function _processQueue(bytes32 resourceType) private {
        uint256[] storage queue = waitingQueue[resourceType];
        if (queue.length == 0) return;
        
        Resource storage resource = resources[resourceType];
        uint256 availableAmount = resource.currentAmount - totalAllocated[resourceType];
        
        // Sort queue by priority (simple insertion sort for gas efficiency with small queues)
        for (uint256 i = 0; i < queue.length && availableAmount > 0; i++) {
            uint256 organismId = queue[i];
            Allocation storage pendingAllocation = allocations[organismId][resourceType];
            
            if (pendingAllocation.amount <= availableAmount) {
                // Activate allocation
                pendingAllocation.isActive = true;
                pendingAllocation.lastClaimBlock = block.number;
                totalAllocated[resourceType] += pendingAllocation.amount;
                availableAmount -= pendingAllocation.amount;
                
                // Remove from queue
                inQueue[resourceType][organismId] = false;
                queue[i] = queue[queue.length - 1];
                queue.pop();
                i--; // Recheck this index
                
                emit ResourceAllocated(organismId, resourceType, pendingAllocation.amount);
            }
        }
    }
    
    // Admin functions
    
    function updateResourceCapacity(
        bytes32 resourceType,
        uint256 newCapacity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        resources[resourceType].totalCapacity = newCapacity;
    }
    
    function updateReplenishRate(
        bytes32 resourceType,
        uint256 newRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        resources[resourceType].replenishRate = newRate;
    }
    
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }
}