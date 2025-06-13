// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title GrowthTracker
 * @author Spore Protocol
 * @notice Tracks biological growth milestones with gas-efficient storage patterns
 * @dev Implements checkpointing system for historical data queries
 */
contract GrowthTracker is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Growth stages enum
    enum GrowthStage {
        SEED,
        GERMINATION,
        VEGETATIVE,
        FLOWERING,
        FRUITING,
        HARVEST,
        DECAY
    }
    
    // Packed struct for gas efficiency (fits in 2 storage slots)
    struct Organism {
        uint128 birthBlock;
        uint64 currentStage;
        uint64 biomass; // in milligrams to avoid decimals
        uint128 lastUpdateBlock;
        uint16 healthScore; // 0-10000 (100.00%)
        uint16 growthRate; // basis points per block
        bool isActive;
    }
    
    // Checkpoint for historical queries
    struct Checkpoint {
        uint128 blockNumber;
        uint128 value;
    }
    
    // Storage
    mapping(uint256 => Organism) public organisms;
    mapping(uint256 => mapping(uint256 => Checkpoint[])) public stageCheckpoints;
    mapping(uint256 => Checkpoint[]) public biomassCheckpoints;
    mapping(uint256 => Checkpoint[]) public healthCheckpoints;
    
    uint256 public nextOrganismId;
    
    // Environmental factors that affect growth
    mapping(uint256 => mapping(bytes32 => uint256)) public environmentalFactors;
    
    // Events
    event OrganismCreated(uint256 indexed organismId, address indexed creator, uint256 species);
    event StageTransition(uint256 indexed organismId, GrowthStage from, GrowthStage to, uint256 blockNumber);
    event BiomassUpdate(uint256 indexed organismId, uint256 oldBiomass, uint256 newBiomass);
    event HealthUpdate(uint256 indexed organismId, uint256 oldHealth, uint256 newHealth);
    event EnvironmentalFactorUpdate(uint256 indexed organismId, bytes32 factor, uint256 value);
    
    // Errors
    error OrganismNotActive(uint256 organismId);
    error InvalidStageTransition(GrowthStage from, GrowthStage to);
    error InvalidHealthScore(uint256 score);
    error InvalidGrowthRate(uint256 rate);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }
    
    /**
     * @notice Creates a new organism with initial parameters
     * @param species Numeric identifier for the species type
     * @param initialBiomass Starting biomass in milligrams
     * @param growthRate Growth rate in basis points per block
     * @return organismId The ID of the newly created organism
     */
    function createOrganism(
        uint256 species,
        uint64 initialBiomass,
        uint16 growthRate
    ) external whenNotPaused returns (uint256 organismId) {
        if (growthRate == 0 || growthRate > 1000) revert InvalidGrowthRate(growthRate);
        
        organismId = nextOrganismId++;
        
        organisms[organismId] = Organism({
            birthBlock: uint128(block.number),
            currentStage: uint64(GrowthStage.SEED),
            biomass: initialBiomass,
            lastUpdateBlock: uint128(block.number),
            healthScore: 10000, // 100%
            growthRate: growthRate,
            isActive: true
        });
        
        // Initialize checkpoints
        _addCheckpoint(stageCheckpoints[organismId][uint256(GrowthStage.SEED)], block.number, 1);
        _addCheckpoint(biomassCheckpoints[organismId], block.number, initialBiomass);
        _addCheckpoint(healthCheckpoints[organismId], block.number, 10000);
        
        emit OrganismCreated(organismId, msg.sender, species);
    }
    
    /**
     * @notice Updates organism growth stage based on biological rules
     * @param organismId The organism to update
     * @param newStage The new growth stage
     */
    function updateGrowthStage(
        uint256 organismId,
        GrowthStage newStage
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        Organism storage organism = organisms[organismId];
        if (!organism.isActive) revert OrganismNotActive(organismId);
        
        GrowthStage currentStage = GrowthStage(organism.currentStage);
        
        // Validate stage transition
        if (!_isValidTransition(currentStage, newStage)) {
            revert InvalidStageTransition(currentStage, newStage);
        }
        
        organism.currentStage = uint64(newStage);
        organism.lastUpdateBlock = uint128(block.number);
        
        // Record checkpoint
        _addCheckpoint(stageCheckpoints[organismId][uint256(newStage)], block.number, 1);
        
        emit StageTransition(organismId, currentStage, newStage, block.number);
    }
    
    /**
     * @notice Updates organism biomass and health based on growth calculations
     * @param organismId The organism to update
     * @param newBiomass New biomass in milligrams
     * @param newHealthScore New health score (0-10000)
     */
    function updateOrganismMetrics(
        uint256 organismId,
        uint64 newBiomass,
        uint16 newHealthScore
    ) external onlyRole(ORACLE_ROLE) whenNotPaused {
        if (newHealthScore > 10000) revert InvalidHealthScore(newHealthScore);
        
        Organism storage organism = organisms[organismId];
        if (!organism.isActive) revert OrganismNotActive(organismId);
        
        uint64 oldBiomass = organism.biomass;
        uint16 oldHealth = organism.healthScore;
        
        organism.biomass = newBiomass;
        organism.healthScore = newHealthScore;
        organism.lastUpdateBlock = uint128(block.number);
        
        // Record checkpoints
        if (oldBiomass != newBiomass) {
            _addCheckpoint(biomassCheckpoints[organismId], block.number, newBiomass);
            emit BiomassUpdate(organismId, oldBiomass, newBiomass);
        }
        
        if (oldHealth != newHealthScore) {
            _addCheckpoint(healthCheckpoints[organismId], block.number, newHealthScore);
            emit HealthUpdate(organismId, oldHealth, newHealthScore);
        }
    }
    
    /**
     * @notice Sets environmental factors that affect organism growth
     * @param organismId The organism affected
     * @param factor Environmental factor name (e.g., "temperature", "humidity")
     * @param value Factor value
     */
    function setEnvironmentalFactor(
        uint256 organismId,
        bytes32 factor,
        uint256 value
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        environmentalFactors[organismId][factor] = value;
        emit EnvironmentalFactorUpdate(organismId, factor, value);
    }
    
    /**
     * @notice Calculates projected biomass based on growth rate
     * @param organismId The organism to calculate for
     * @return projectedBiomass The calculated biomass
     */
    function calculateProjectedBiomass(uint256 organismId) external view returns (uint256 projectedBiomass) {
        Organism memory organism = organisms[organismId];
        if (!organism.isActive) return 0;
        
        uint256 blocksPassed = block.number - organism.lastUpdateBlock;
        uint256 growthAmount = (uint256(organism.biomass) * organism.growthRate * blocksPassed) / 10000;
        
        // Apply health modifier
        growthAmount = (growthAmount * organism.healthScore) / 10000;
        
        projectedBiomass = organism.biomass + growthAmount;
    }
    
    /**
     * @notice Gets organism metrics at a specific block number
     * @param organismId The organism to query
     * @param blockNumber The block number to query at
     * @return biomass The biomass at the given block
     * @return health The health score at the given block
     * @return stage The growth stage at the given block
     */
    function getHistoricalMetrics(
        uint256 organismId,
        uint256 blockNumber
    ) external view returns (uint256 biomass, uint256 health, GrowthStage stage) {
        biomass = _getCheckpointValue(biomassCheckpoints[organismId], blockNumber);
        health = _getCheckpointValue(healthCheckpoints[organismId], blockNumber);
        
        // Find active stage at block
        for (uint i = 0; i <= uint(GrowthStage.DECAY); i++) {
            if (_getCheckpointValue(stageCheckpoints[organismId][i], blockNumber) > 0) {
                stage = GrowthStage(i);
            }
        }
    }
    
    /**
     * @notice Deactivates an organism (death/harvest)
     * @param organismId The organism to deactivate
     */
    function deactivateOrganism(uint256 organismId) external onlyRole(OPERATOR_ROLE) {
        Organism storage organism = organisms[organismId];
        organism.isActive = false;
        organism.currentStage = uint64(GrowthStage.DECAY);
        
        emit StageTransition(organismId, GrowthStage(organism.currentStage), GrowthStage.DECAY, block.number);
    }
    
    // Internal functions
    
    function _isValidTransition(GrowthStage from, GrowthStage to) private pure returns (bool) {
        // Define valid stage transitions
        if (from == GrowthStage.SEED && to == GrowthStage.GERMINATION) return true;
        if (from == GrowthStage.GERMINATION && to == GrowthStage.VEGETATIVE) return true;
        if (from == GrowthStage.VEGETATIVE && (to == GrowthStage.FLOWERING || to == GrowthStage.HARVEST)) return true;
        if (from == GrowthStage.FLOWERING && (to == GrowthStage.FRUITING || to == GrowthStage.HARVEST)) return true;
        if (from == GrowthStage.FRUITING && to == GrowthStage.HARVEST) return true;
        if (to == GrowthStage.DECAY) return true; // Can decay from any stage
        
        return false;
    }
    
    function _addCheckpoint(Checkpoint[] storage checkpoints, uint256 blockNumber, uint256 value) private {
        if (checkpoints.length > 0 && checkpoints[checkpoints.length - 1].blockNumber == blockNumber) {
            checkpoints[checkpoints.length - 1].value = uint128(value);
        } else {
            checkpoints.push(Checkpoint({
                blockNumber: uint128(blockNumber),
                value: uint128(value)
            }));
        }
    }
    
    function _getCheckpointValue(Checkpoint[] storage checkpoints, uint256 blockNumber) private view returns (uint256) {
        if (checkpoints.length == 0) return 0;
        
        // Binary search
        uint256 low = 0;
        uint256 high = checkpoints.length;
        
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (checkpoints[mid].blockNumber > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        
        return low == 0 ? 0 : checkpoints[low - 1].value;
    }
    
    // Admin functions
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}