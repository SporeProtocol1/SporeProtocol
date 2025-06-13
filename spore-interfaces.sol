// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IGrowthTracker
 * @notice Interface for the GrowthTracker contract
 */
interface IGrowthTracker {
    enum GrowthStage {
        SEED,
        GERMINATION,
        VEGETATIVE,
        FLOWERING,
        FRUITING,
        HARVEST,
        DECAY
    }
    
    struct Organism {
        uint128 birthBlock;
        uint64 currentStage;
        uint64 biomass;
        uint128 lastUpdateBlock;
        uint16 healthScore;
        uint16 growthRate;
        bool isActive;
    }
    
    function organisms(uint256) external view returns (
        uint128 birthBlock,
        uint64 currentStage,
        uint64 biomass,
        uint128 lastUpdateBlock,
        uint16 healthScore,
        uint16 growthRate,
        bool isActive
    );
    
    function createOrganism(uint256 species, uint64 initialBiomass, uint16 growthRate) external returns (uint256);
    function updateGrowthStage(uint256 organismId, GrowthStage newStage) external;
    function updateOrganismMetrics(uint256 organismId, uint64 newBiomass, uint16 newHealthScore) external;
    function calculateProjectedBiomass(uint256 organismId) external view returns (uint256);
    function getHistoricalMetrics(uint256 organismId, uint256 blockNumber) external view returns (uint256 biomass, uint256 health, GrowthStage stage);
    function getCurrentMetrics(uint256 organismId) external view returns (uint256 stage, uint256 health, uint256 biomass);
}

/**
 * @title IBioNFT
 * @notice Interface for the BioNFT contract
 */
interface IBioNFT {
    struct GeneticProfile {
        uint16 growthSpeed;
        uint16 diseaseResistance;
        uint16 yieldPotential;
        uint16 adaptability;
        uint8 generation;
        uint8 rarity;
    }
    
    function mintBioNFT(address to, string memory species, uint256 growthTrackerId, uint256[2] memory parentIds) external returns (uint256);
    function updateMetadata(uint256 tokenId, bytes memory signature, string memory newImageURI) external;
    function breed(uint256 parentTokenId1, uint256 parentTokenId2, uint256 growthTrackerId) external returns (uint256);
    function getOrganismData(uint256 tokenId) external view returns (string memory species, uint256 stage, uint256 health, uint256 biomass, GeneticProfile memory genetics);
}

/**
 * @title IResourcePool
 * @notice Interface for the ResourcePool contract
 */
interface IResourcePool {
    function allocateResource(uint256 organismId, bytes32 resourceType, uint256 amount, uint256 priority) external;
    function claimResource(uint256 organismId, bytes32 resourceType) external returns (uint256);
    function releaseResource(uint256 organismId, bytes32 resourceType, uint256 amount) external;
    function getResourceAvailability(bytes32 resourceType) external view returns (uint256 available, uint256 capacity, uint256 allocated);
}

/**
 * @title ISwarmCoordinator
 * @notice Interface for the SwarmCoordinator contract
 */
interface ISwarmCoordinator {
    enum SwarmMode {
        IDLE,
        FORAGING,
        FORMATION,
        EXPLORATION,
        COLLECTIVE_TRANSPORT,
        AREA_COVERAGE,
        PERIMETER_DEFENSE,
        EMERGENT
    }
    
    enum Priority {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }
    
    function registerRobot(address controller, uint256 x, uint256 y, uint256 capacity) external returns (uint256);
    function createSwarm(string memory name, SwarmMode mode, uint256 minRobots, uint256 maxRobots, bytes32 consensusRules) external returns (uint256);
    function joinSwarm(uint256 robotId, uint256 swarmId) external;
    function createTask(string memory description, uint256 swarmId, Priority priority, uint256 reward, uint256 duration, uint256 minRobots, bytes memory metadata) external returns (uint256);
    function updateRobotState(uint256 x, uint256 y, uint256 z, uint256 battery) external;
}

/**
 * @title IBioOracle
 * @notice Interface for the BioOracle contract
 */
interface IBioOracle {
    enum DataType {
        TEMPERATURE,
        HUMIDITY,
        PH_LEVEL,
        LIGHT_INTENSITY,
        CO2_LEVEL,
        NUTRIENT_CONCENTRATION,
        GROWTH_RATE,
        BIOMASS,
        HEALTH_SCORE,
        ELECTRICAL_SIGNAL
    }
    
    function submitData(uint256 organismId, DataType dataType, int256 value, bytes32 proofHash) external payable returns (uint256);
    function validateData(uint256 dataPointId, bool approve, uint256 confidence) external;
    function getLatestValue(uint256 organismId, DataType dataType) external view returns (int256 value, uint256 timestamp, uint256 confidence);
    function getAggregatedData(uint256 organismId, DataType dataType, uint256 numPoints) external view returns (int256[] memory values, uint256[] memory timestamps, int256 average);
}

/**
 * @title IDecayHandler
 * @notice Interface for the DecayHandler contract
 */
interface IDecayHandler {
    function initiateDecay(uint256 organismId) external;
    function processDecay(uint256 organismId) external returns (uint256 compostGenerated);
    function claimCompost(uint256 amount) external;
    function getDecayProgress(uint256 organismId) external view returns (uint256 progress, uint256 compostAvailable);
}