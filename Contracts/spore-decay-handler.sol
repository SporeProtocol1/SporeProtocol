// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGrowthTracker.sol";
import "./interfaces/IResourcePool.sol";

/**
 * @title DecayHandler
 * @author Spore Protocol
 * @notice Manages organism decay and resource recycling
 * @dev Implements composting mechanics and nutrient recovery
 */
contract DecayHandler is AccessControl, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant COMPOSTER_ROLE = keccak256("COMPOSTER_ROLE");
    
    // Decay stages
    enum DecayStage {
        FRESH,
        ACTIVE_DECAY,
        ADVANCED_DECAY,
        DRY_REMAINS,
        COMPOST
    }
    
    struct DecayingOrganism {
        uint256 growthTrackerId;
        uint256 initialBiomass;
        uint256 remainingBiomass;
        uint256 decayStartBlock;
        DecayStage stage;
        uint256 compostGenerated;
        address owner;
        bool isActive;
    }
    
    struct CompostingParameters {
        uint256 decayRate; // Biomass loss per block (basis points)
        uint256 compostYield; // Compost generated per biomass unit (basis points)
        uint256 optimalTemperature; // Scaled by 100 (e.g., 2500 = 25°C)
        uint256 optimalHumidity; // 0-10000 (100%)
        uint256 carbonNitrogenRatio; // Optimal C:N ratio * 100
    }
    
    struct EnvironmentalConditions {
        int256 temperature;
        uint256 humidity;
        uint256 oxygenLevel;
        uint256 microbialActivity;
        uint256 lastUpdateBlock;
    }
    
    struct CompostToken {
        uint256 totalSupply;
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
    }
    
    // Storage
    mapping(uint256 => DecayingOrganism) public decayingOrganisms;
    mapping(uint256 => EnvironmentalConditions) public environmentalConditions;
    mapping(DecayStage => CompostingParameters) public stageParameters;
    
    // Compost token (internal accounting)
    CompostToken private compostToken;
    mapping(address => uint256) public claimableCompost;
    
    // Resource recovery
    mapping(bytes32 => uint256) public recoveredResources;
    uint256 public totalCompostGenerated;
    uint256 public totalBiomassProcessed;
    
    // External contracts
    IGrowthTracker public immutable growthTracker;
    IResourcePool public immutable resourcePool;
    
    uint256 public nextDecayId;
    uint256 private constant BLOCKS_PER_DAY = 7200; // Assuming 12 second blocks
    
    // Events
    event DecayInitiated(uint256 indexed decayId, uint256 indexed growthTrackerId, uint256 biomass, address owner);
    event DecayStageTransition(uint256 indexed decayId, DecayStage from, DecayStage to);
    event CompostGenerated(uint256 indexed decayId, uint256 amount);
    event ResourcesRecovered(uint256 indexed decayId, bytes32 resourceType, uint256 amount);
    event EnvironmentalUpdate(uint256 indexed decayId, int256 temperature, uint256 humidity);
    event CompostClaimed(address indexed user, uint256 amount);
    event DecayAccelerated(uint256 indexed decayId, uint256 factor);
    
    // Errors
    error OrganismNotDecaying();
    error InvalidDecayStage();
    error InsufficientCompost();
    error DecayNotComplete();
    error UnauthorizedOwner();
    
    modifier onlyOrganismOwner(uint256 decayId) {
        if (decayingOrganisms[decayId].owner != msg.sender && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert UnauthorizedOwner();
        }
        _;
    }
    
    constructor(address _growthTracker, address _resourcePool) {
        require(_growthTracker != address(0) && _resourcePool != address(0), "Invalid addresses");
        
        growthTracker = IGrowthTracker(_growthTracker);
        resourcePool = IResourcePool(_resourcePool);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(COMPOSTER_ROLE, msg.sender);
        
        _initializeDecayParameters();
    }
    
    /**
     * @notice Initiates decay process for a harvested organism
     * @param growthTrackerId The organism from GrowthTracker
     * @return decayId The decay process ID
     */
    function initiateDecay(uint256 growthTrackerId) external returns (uint256 decayId) {
        // Verify organism is in decay stage
        (
            ,
            uint64 currentStage,
            uint64 biomass,
            ,
            ,
            ,
            bool isActive
        ) = growthTracker.organisms(growthTrackerId);
        
        require(isActive, "Organism not active");
        require(IGrowthTracker.GrowthStage(currentStage) == IGrowthTracker.GrowthStage.DECAY, "Not in decay stage");
        
        decayId = nextDecayId++;
        
        decayingOrganisms[decayId] = DecayingOrganism({
            growthTrackerId: growthTrackerId,
            initialBiomass: biomass,
            remainingBiomass: biomass,
            decayStartBlock: block.number,
            stage: DecayStage.FRESH,
            compostGenerated: 0,
            owner: msg.sender,
            isActive: true
        });
        
        // Initialize environmental conditions
        environmentalConditions[decayId] = EnvironmentalConditions({
            temperature: 2000, // 20°C default
            humidity: 6000, // 60% default
            oxygenLevel: 8000, // 80% default
            microbialActivity: 5000, // 50% default
            lastUpdateBlock: block.number
        });
        
        emit DecayInitiated(decayId, growthTrackerId, biomass, msg.sender);
    }
    
    /**
     * @notice Processes decay based on environmental conditions
     * @param decayId The decay process to update
     * @return compostGenerated Amount of compost generated
     */
    function processDecay(uint256 decayId) external nonReentrant returns (uint256 compostGenerated) {
        DecayingOrganism storage organism = decayingOrganisms[decayId];
        if (!organism.isActive) revert OrganismNotDecaying();
        
        EnvironmentalConditions memory conditions = environmentalConditions[decayId];
        uint256 blocksPassed = block.number - conditions.lastUpdateBlock;
        
        if (blocksPassed == 0) return 0;
        
        CompostingParameters memory params = stageParameters[organism.stage];
        
        // Calculate decay rate based on environmental conditions
        uint256 effectiveDecayRate = _calculateEffectiveDecayRate(decayId, params);
        
        // Process biomass decay
        uint256 biomassDecayed = (organism.remainingBiomass * effectiveDecayRate * blocksPassed) / (10000 * BLOCKS_PER_DAY);
        biomassDecayed = biomassDecayed > organism.remainingBiomass ? organism.remainingBiomass : biomassDecayed;
        
        organism.remainingBiomass -= biomassDecayed;
        totalBiomassProcessed += biomassDecayed;
        
        // Generate compost
        compostGenerated = (biomassDecayed * params.compostYield) / 10000;
        organism.compostGenerated += compostGenerated;
        totalCompostGenerated += compostGenerated;
        
        // Update compost balance
        claimableCompost[organism.owner] += compostGenerated;
        compostToken.totalSupply += compostGenerated;
        compostToken.balances[organism.owner] += compostGenerated;
        
        // Check for stage transition
        DecayStage newStage = _determineDecayStage(organism);
        if (newStage != organism.stage) {
            emit DecayStageTransition(decayId, organism.stage, newStage);
            organism.stage = newStage;
            
            // Recover resources at stage transitions
            _recoverResources(decayId, biomassDecayed);
        }
        
        environmentalConditions[decayId].lastUpdateBlock = block.number;
        
        emit CompostGenerated(decayId, compostGenerated);
        
        // Mark as complete if fully decayed
        if (organism.remainingBiomass == 0 || organism.stage == DecayStage.COMPOST) {
            organism.isActive = false;
        }
    }
    
    /**
     * @notice Updates environmental conditions affecting decay
     * @param decayId The decay process
     * @param temperature New temperature (scaled by 100)
     * @param humidity New humidity (0-10000)
     * @param oxygenLevel Oxygen level (0-10000)
     */
    function updateEnvironmentalConditions(
        uint256 decayId,
        int256 temperature,
        uint256 humidity,
        uint256 oxygenLevel
    ) external onlyRole(OPERATOR_ROLE) {
        require(humidity <= 10000 && oxygenLevel <= 10000, "Invalid parameters");
        
        EnvironmentalConditions storage conditions = environmentalConditions[decayId];
        conditions.temperature = temperature;
        conditions.humidity = humidity;
        conditions.oxygenLevel = oxygenLevel;
        
        // Update microbial activity based on conditions
        conditions.microbialActivity = _calculateMicrobialActivity(temperature, humidity, oxygenLevel);
        
        emit EnvironmentalUpdate(decayId, temperature, humidity);
    }
    
    /**
     * @notice Accelerates decay using additives
     * @param decayId The decay process
     * @param additiveType Type of additive used
     */
    function accelerateDecay(uint256 decayId, bytes32 additiveType) external onlyOrganismOwner(decayId) {
        DecayingOrganism storage organism = decayingOrganisms[decayId];
        if (!organism.isActive) revert OrganismNotDecaying();
        
        uint256 accelerationFactor = _getAccelerationFactor(additiveType);
        
        // Process accelerated decay
        uint256 additionalDecay = (organism.remainingBiomass * accelerationFactor) / 10000;
        organism.remainingBiomass -= additionalDecay > organism.remainingBiomass ? organism.remainingBiomass : additionalDecay;
        
        emit DecayAccelerated(decayId, accelerationFactor);
    }
    
    /**
     * @notice Claims accumulated compost
     * @param amount Amount to claim
     */
    function claimCompost(uint256 amount) external nonReentrant {
        if (claimableCompost[msg.sender] < amount) revert InsufficientCompost();
        
        claimableCompost[msg.sender] -= amount;
        
        // Transfer compost token or convert to resources
        _transferCompost(msg.sender, amount);
        
        emit CompostClaimed(msg.sender, amount);
    }
    
    /**
     * @notice Batch processes multiple decay operations
     * @param decayIds Array of decay IDs to process
     */
    function batchProcessDecay(uint256[] calldata decayIds) external {
        for (uint256 i = 0; i < decayIds.length; i++) {
            processDecay(decayIds[i]);
        }
    }
    
    /**
     * @notice Gets current decay status
     * @param decayId The decay process to query
     * @return stage Current decay stage
     * @return progress Decay progress percentage (0-10000)
     * @return compostAvailable Compost ready to claim
     * @return estimatedCompletion Estimated blocks until complete
     */
    function getDecayStatus(uint256 decayId) external view returns (
        DecayStage stage,
        uint256 progress,
        uint256 compostAvailable,
        uint256 estimatedCompletion
    ) {
        DecayingOrganism memory organism = decayingOrganisms[decayId];
        
        stage = organism.stage;
        progress = organism.initialBiomass > 0 
            ? ((organism.initialBiomass - organism.remainingBiomass) * 10000) / organism.initialBiomass 
            : 10000;
        compostAvailable = claimableCompost[organism.owner];
        
        if (organism.isActive && organism.remainingBiomass > 0) {
            CompostingParameters memory params = stageParameters[organism.stage];
            uint256 effectiveDecayRate = _calculateEffectiveDecayRate(decayId, params);
            estimatedCompletion = (organism.remainingBiomass * 10000 * BLOCKS_PER_DAY) / 
                                (organism.initialBiomass * effectiveDecayRate);
        }
    }
    
    /**
     * @notice Converts compost to specific resources
     * @param amount Amount of compost to convert
     * @param targetResource Resource type to create
     */
    function convertCompostToResource(
        uint256 amount,
        bytes32 targetResource
    ) external nonReentrant {
        if (compostToken.balances[msg.sender] < amount) revert InsufficientCompost();
        
        compostToken.balances[msg.sender] -= amount;
        compostToken.totalSupply -= amount;
        
        // Calculate resource generation (simplified)
        uint256 resourceAmount = _calculateResourceConversion(amount, targetResource);
        
        // Add to resource pool
        // In production, would interact with ResourcePool contract
        recoveredResources[targetResource] += resourceAmount;
        
        emit ResourcesRecovered(0, targetResource, resourceAmount);
    }
    
    // Internal functions
    
    function _initializeDecayParameters() private {
        // Fresh stage - slow initial decay
        stageParameters[DecayStage.FRESH] = CompostingParameters({
            decayRate: 100, // 1% per day
            compostYield: 0, // No compost yet
            optimalTemperature: 2500, // 25°C
            optimalHumidity: 7000, // 70%
            carbonNitrogenRatio: 3000 // 30:1
        });
        
        // Active decay - fastest decomposition
        stageParameters[DecayStage.ACTIVE_DECAY] = CompostingParameters({
            decayRate: 500, // 5% per day
            compostYield: 2000, // 20% compost yield
            optimalTemperature: 3500, // 35°C
            optimalHumidity: 6000, // 60%
            carbonNitrogenRatio: 2500 // 25:1
        });
        
        // Advanced decay - slower, more compost
        stageParameters[DecayStage.ADVANCED_DECAY] = CompostingParameters({
            decayRate: 300, // 3% per day
            compostYield: 4000, // 40% compost yield
            optimalTemperature: 3000, // 30°C
            optimalHumidity: 5000, // 50%
            carbonNitrogenRatio: 2000 // 20:1
        });
        
        // Dry remains - very slow
        stageParameters[DecayStage.DRY_REMAINS] = CompostingParameters({
            decayRate: 50, // 0.5% per day
            compostYield: 6000, // 60% compost yield
            optimalTemperature: 2500, // 25°C
            optimalHumidity: 4000, // 40%
            carbonNitrogenRatio: 1500 // 15:1
        });
        
        // Compost - stable
        stageParameters[DecayStage.COMPOST] = CompostingParameters({
            decayRate: 0, // No further decay
            compostYield: 10000, // 100% is compost
            optimalTemperature: 2000, // 20°C
            optimalHumidity: 5000, // 50%
            carbonNitrogenRatio: 1000 // 10:1
        });
    }
    
    function _calculateEffectiveDecayRate(
        uint256 decayId,
        CompostingParameters memory params
    ) private view returns (uint256) {
        EnvironmentalConditions memory conditions = environmentalConditions[decayId];
        
        // Calculate environmental efficiency (0-10000)
        uint256 tempEfficiency = _calculateTemperatureEfficiency(conditions.temperature, params.optimalTemperature);
        uint256 humidityEfficiency = _calculateHumidityEfficiency(conditions.humidity, params.optimalHumidity);
        uint256 oxygenEfficiency = (conditions.oxygenLevel * 10000) / 10000; // Linear relationship
        
        // Combined efficiency
        uint256 environmentalEfficiency = (tempEfficiency + humidityEfficiency + oxygenEfficiency) / 3;
        
        // Apply microbial activity modifier
        uint256 microbialModifier = (conditions.microbialActivity * 10000) / 10000;
        
        // Calculate final decay rate
        return (params.decayRate * environmentalEfficiency * microbialModifier) / 100000000;
    }
    
    function _calculateTemperatureEfficiency(int256 current, uint256 optimal) private pure returns (uint256) {
        uint256 optimalInt = uint256(int256(optimal));
        uint256 currentAbs = current >= 0 ? uint256(current) : 0;
        
        uint256 difference = currentAbs > optimalInt 
            ? currentAbs - optimalInt 
            : optimalInt - currentAbs;
            
        if (difference > optimalInt) return 0;
        
        return 10000 - ((difference * 10000) / optimalInt);
    }
    
    function _calculateHumidityEfficiency(uint256 current, uint256 optimal) private pure returns (uint256) {
        uint256 difference = current > optimal ? current - optimal : optimal - current;
        if (difference > optimal) return 0;
        
        return 10000 - ((difference * 10000) / optimal);
    }
    
    function _calculateMicrobialActivity(
        int256 temperature,
        uint256 humidity,
        uint256 oxygen
    ) private pure returns (uint256) {
        // Simplified calculation
        uint256 tempFactor = temperature > 0 && temperature < 5000 
            ? uint256(temperature) / 5 
            : 0;
        
        uint256 humidityFactor = humidity / 2;
        uint256 oxygenFactor = oxygen / 2;
        
        return (tempFactor + humidityFactor + oxygenFactor) / 3;
    }
    
    function _determineDecayStage(DecayingOrganism memory organism) private pure returns (DecayStage) {
        uint256 percentRemaining = (organism.remainingBiomass * 100) / organism.initialBiomass;
        
        if (percentRemaining > 90) return DecayStage.FRESH;
        if (percentRemaining > 60) return DecayStage.ACTIVE_DECAY;
        if (percentRemaining > 30) return DecayStage.ADVANCED_DECAY;
        if (percentRemaining > 5) return DecayStage.DRY_REMAINS;
        return DecayStage.COMPOST;
    }
    
    function _recoverResources(uint256 decayId, uint256 biomassDecayed) private {
        // Recover nitrogen, phosphorus, potassium based on biomass
        uint256 nitrogen = (biomassDecayed * 300) / 10000; // 3% nitrogen
        uint256 phosphorus = (biomassDecayed * 50) / 10000; // 0.5% phosphorus
        uint256 potassium = (biomassDecayed * 200) / 10000; // 2% potassium
        
        recoveredResources[keccak256("NITROGEN")] += nitrogen;
        recoveredResources[keccak256("PHOSPHORUS")] += phosphorus;
        recoveredResources[keccak256("POTASSIUM")] += potassium;
        
        emit ResourcesRecovered(decayId, keccak256("NITROGEN"), nitrogen);
        emit ResourcesRecovered(decayId, keccak256("PHOSPHORUS"), phosphorus);
        emit ResourcesRecovered(decayId, keccak256("POTASSIUM"), potassium);
    }
    
    function _getAccelerationFactor(bytes32 additiveType) private pure returns (uint256) {
        if (additiveType == keccak256("ENZYMES")) return 2000; // 20% acceleration
        if (additiveType == keccak256("MICROBES")) return 3000; // 30% acceleration
        if (additiveType == keccak256("NITROGEN_BOOST")) return 1500; // 15% acceleration
        return 1000; // 10% default
    }
    
    function _calculateResourceConversion(uint256 compostAmount, bytes32 resource) private pure returns (uint256) {
        // Simplified conversion rates
        if (resource == keccak256("NITROGEN")) return compostAmount * 3 / 100;
        if (resource == keccak256("PHOSPHORUS")) return compostAmount * 1 / 200;
        if (resource == keccak256("POTASSIUM")) return compostAmount * 2 / 100;
        return compostAmount / 100; // Default 1% conversion
    }
    
    function _transferCompost(address to, uint256 amount) private {
        // In production, this would interface with an ERC20 compost token
        // For now, it's tracked internally
        compostToken.balances[to] += amount;
    }
    
    // Admin functions
    
    function updateDecayParameters(
        DecayStage stage,
        uint256 decayRate,
        uint256 compostYield,
        uint256 optimalTemp,
        uint256 optimalHumidity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stageParameters[stage] = CompostingParameters({
            decayRate: decayRate,
            compostYield: compostYield,
            optimalTemperature: optimalTemp,
            optimalHumidity: optimalHumidity,
            carbonNitrogenRatio: stageParameters[stage].carbonNitrogenRatio
        });
    }
    
    function withdrawRecoveredResources(
        bytes32 resourceType,
        uint256 amount,
        address recipient
    ) external onlyRole(OPERATOR_ROLE) {
        require(recoveredResources[resourceType] >= amount, "Insufficient resources");
        recoveredResources[resourceType] -= amount;
        
        // In production, would transfer to ResourcePool or recipient
    }
}