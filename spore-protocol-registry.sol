// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IGrowthTracker.sol";
import "./interfaces/IBioNFT.sol";
import "./interfaces/IResourcePool.sol";
import "./interfaces/ISwarmCoordinator.sol";
import "./interfaces/IBioOracle.sol";
import "./interfaces/IDecayHandler.sol";

/**
 * @title SporeProtocolRegistry
 * @author Spore Protocol
 * @notice Central registry and orchestrator for all Spore Protocol contracts
 * @dev Upgradeable pattern for future protocol enhancements
 */
contract SporeProtocolRegistry is 
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PROTOCOL_ADMIN = keccak256("PROTOCOL_ADMIN");
    bytes32 public constant FEE_MANAGER = keccak256("FEE_MANAGER");
    
    // Protocol version
    uint256 public constant VERSION = 1;
    
    // Core contract addresses
    address public growthTracker;
    address public bioNFT;
    address public resourcePool;
    address public swarmCoordinator;
    address public bioOracle;
    address public decayHandler;
    
    // Protocol fees (basis points)
    uint256 public protocolFee;
    uint256 public constant MAX_PROTOCOL_FEE = 500; // 5% max
    address public feeRecipient;
    
    // Registered organisms and their metadata
    struct OrganismRegistration {
        uint256 growthTrackerId;
        uint256 bioNFTId;
        address owner;
        uint256 registrationBlock;
        bool isActive;
        string species;
        bytes metadata;
    }
    
    // Integration endpoints
    struct IntegrationEndpoint {
        address contractAddress;
        bool isActive;
        uint256 apiVersion;
        string endpoint;
        bytes32 apiKey; // Hashed API key for external integrations
    }
    
    // Protocol statistics
    struct ProtocolStats {
        uint256 totalOrganisms;
        uint256 activeOrganisms;
        uint256 totalBiomassTracked;
        uint256 totalCompostGenerated;
        uint256 totalTransactions;
        uint256 totalFeesCollected;
    }
    
    // Storage
    mapping(uint256 => OrganismRegistration) public organismRegistry;
    mapping(address => uint256[]) public userOrganisms;
    mapping(string => IntegrationEndpoint) public integrations;
    mapping(address => bool) public whitelistedContracts;
    
    ProtocolStats public protocolStats;
    uint256 public nextOrganismId;
    
    // Events
    event ContractsUpdated(
        address growthTracker,
        address bioNFT,
        address resourcePool,
        address swarmCoordinator,
        address bioOracle,
        address decayHandler
    );
    event OrganismRegistered(uint256 indexed organismId, address indexed owner, string species);
    event IntegrationAdded(string indexed name, address indexed contractAddress);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesCollected(address indexed from, uint256 amount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    
    // Errors
    error InvalidAddress();
    error UnauthorizedAccess();
    error OrganismNotFound();
    error IntegrationNotActive();
    error FeeExceedsMaximum();
    error InsufficientPayment();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the protocol registry
     * @param _admin Protocol admin address
     * @param _feeRecipient Fee recipient address
     * @param _protocolFee Initial protocol fee in basis points
     */
    function initialize(
        address _admin,
        address _feeRecipient,
        uint256 _protocolFee
    ) public initializer {
        if (_admin == address(0) || _feeRecipient == address(0)) revert InvalidAddress();
        if (_protocolFee > MAX_PROTOCOL_FEE) revert FeeExceedsMaximum();
        
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROTOCOL_ADMIN, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(FEE_MANAGER, _admin);
        
        feeRecipient = _feeRecipient;
        protocolFee = _protocolFee;
    }
    
    /**
     * @notice Updates core protocol contracts
     * @param _growthTracker GrowthTracker contract address
     * @param _bioNFT BioNFT contract address
     * @param _resourcePool ResourcePool contract address
     * @param _swarmCoordinator SwarmCoordinator contract address
     * @param _bioOracle BioOracle contract address
     * @param _decayHandler DecayHandler contract address
     */
    function updateCoreContracts(
        address _growthTracker,
        address _bioNFT,
        address _resourcePool,
        address _swarmCoordinator,
        address _bioOracle,
        address _decayHandler
    ) external onlyRole(PROTOCOL_ADMIN) {
        if (_growthTracker == address(0) || _bioNFT == address(0) || 
            _resourcePool == address(0) || _swarmCoordinator == address(0) ||
            _bioOracle == address(0) || _decayHandler == address(0)) {
            revert InvalidAddress();
        }
        
        growthTracker = _growthTracker;
        bioNFT = _bioNFT;
        resourcePool = _resourcePool;
        swarmCoordinator = _swarmCoordinator;
        bioOracle = _bioOracle;
        decayHandler = _decayHandler;
        
        // Whitelist core contracts
        whitelistedContracts[_growthTracker] = true;
        whitelistedContracts[_bioNFT] = true;
        whitelistedContracts[_resourcePool] = true;
        whitelistedContracts[_swarmCoordinator] = true;
        whitelistedContracts[_bioOracle] = true;
        whitelistedContracts[_decayHandler] = true;
        
        emit ContractsUpdated(
            _growthTracker,
            _bioNFT,
            _resourcePool,
            _swarmCoordinator,
            _bioOracle,
            _decayHandler
        );
    }
    
    /**
     * @notice Registers a new organism in the protocol
     * @param species Organism species
     * @param initialBiomass Starting biomass
     * @param growthRate Growth rate parameter
     * @param metadata Additional organism data
     * @return organismId Protocol-wide organism ID
     */
    function registerOrganism(
        string memory species,
        uint64 initialBiomass,
        uint16 growthRate,
        bytes memory metadata
    ) external payable whenNotPaused nonReentrant returns (uint256 organismId) {
        uint256 requiredFee = _calculateProtocolFee(0.01 ether); // Base registration fee
        if (msg.value < requiredFee) revert InsufficientPayment();
        
        // Create organism in GrowthTracker
        uint256 growthTrackerId = IGrowthTracker(growthTracker).createOrganism(
            uint256(keccak256(bytes(species))),
            initialBiomass,
            growthRate
        );
        
        // Mint BioNFT
        uint256 bioNFTId = IBioNFT(bioNFT).mintBioNFT(
            msg.sender,
            species,
            growthTrackerId,
            [uint256(0), uint256(0)] // No parents for genesis
        );
        
        // Register in protocol
        organismId = nextOrganismId++;
        
        organismRegistry[organismId] = OrganismRegistration({
            growthTrackerId: growthTrackerId,
            bioNFTId: bioNFTId,
            owner: msg.sender,
            registrationBlock: block.number,
            isActive: true,
            species: species,
            metadata: metadata
        });
        
        userOrganisms[msg.sender].push(organismId);
        
        // Update stats
        protocolStats.totalOrganisms++;
        protocolStats.activeOrganisms++;
        protocolStats.totalTransactions++;
        protocolStats.totalFeesCollected += msg.value;
        
        // Transfer fees
        _transferFees(msg.value);
        
        emit OrganismRegistered(organismId, msg.sender, species);
    }
    
    /**
     * @notice Creates a complete organism lifecycle with resources
     * @param species Organism species
     * @param resourceAllocations Initial resource allocations
     * @return organismId The created organism ID
     * @return growthTrackerId The growth tracker ID
     * @return bioNFTId The NFT token ID
     */
    function createOrganismWithResources(
        string memory species,
        bytes32[] memory resourceTypes,
        uint256[] memory resourceAmounts
    ) external payable whenNotPaused returns (
        uint256 organismId,
        uint256 growthTrackerId,
        uint256 bioNFTId
    ) {
        require(resourceTypes.length == resourceAmounts.length, "Array mismatch");
        
        // Register organism first
        organismId = registerOrganism(species, 100, 50, "");
        OrganismRegistration memory reg = organismRegistry[organismId];
        growthTrackerId = reg.growthTrackerId;
        bioNFTId = reg.bioNFTId;
        
        // Allocate resources
        for (uint256 i = 0; i < resourceTypes.length; i++) {
            IResourcePool(resourcePool).allocateResource(
                growthTrackerId,
                resourceTypes[i],
                resourceAmounts[i],
                50 // Default priority
            );
        }
    }
    
    /**
     * @notice Submits biological data through the registry
     * @param organismId Protocol organism ID
     * @param dataType Type of data
     * @param value Data value
     * @return dataPointId Created data point ID
     */
    function submitOrganismData(
        uint256 organismId,
        IBioOracle.DataType dataType,
        int256 value
    ) external payable returns (uint256 dataPointId) {
        OrganismRegistration memory reg = organismRegistry[organismId];
        if (!reg.isActive) revert OrganismNotFound();
        if (reg.owner != msg.sender && !hasRole(PROTOCOL_ADMIN, msg.sender)) {
            revert UnauthorizedAccess();
        }
        
        uint256 requiredFee = _calculateProtocolFee(0.0001 ether);
        if (msg.value < requiredFee) revert InsufficientPayment();
        
        dataPointId = IBioOracle(bioOracle).submitData{value: msg.value - requiredFee}(
            reg.growthTrackerId,
            dataType,
            value,
            keccak256(abi.encodePacked(block.timestamp, msg.sender))
        );
        
        protocolStats.totalTransactions++;
        protocolStats.totalFeesCollected += requiredFee;
        
        _transferFees(requiredFee);
    }
    
    /**
     * @notice Registers an external integration
     * @param name Integration name
     * @param endpoint API endpoint
     * @param contractAddress Integration contract
     * @param apiKeyHash Hashed API key
     */
    function registerIntegration(
        string memory name,
        string memory endpoint,
        address contractAddress,
        bytes32 apiKeyHash
    ) external onlyRole(PROTOCOL_ADMIN) {
        integrations[name] = IntegrationEndpoint({
            contractAddress: contractAddress,
            isActive: true,
            apiVersion: 1,
            endpoint: endpoint,
            apiKey: apiKeyHash
        });
        
        if (contractAddress != address(0)) {
            whitelistedContracts[contractAddress] = true;
        }
        
        emit IntegrationAdded(name, contractAddress);
    }
    
    /**
     * @notice Gets comprehensive organism data
     * @param organismId Protocol organism ID
     * @return registration Complete registration data
     * @return currentStage Current growth stage
     * @return health Current health score
     * @return biomass Current biomass
     * @return genetics Genetic profile from NFT
     */
    function getOrganismData(uint256 organismId) external view returns (
        OrganismRegistration memory registration,
        uint256 currentStage,
        uint256 health,
        uint256 biomass,
        IBioNFT.GeneticProfile memory genetics
    ) {
        registration = organismRegistry[organismId];
        if (!registration.isActive) revert OrganismNotFound();
        
        // Get growth data
        (currentStage, health, biomass) = IGrowthTracker(growthTracker)
            .getCurrentMetrics(registration.growthTrackerId);
        
        // Get genetic data
        (, , , , genetics) = IBioNFT(bioNFT).getOrganismData(registration.bioNFTId);
    }
    
    /**
     * @notice Gets all organisms owned by a user
     * @param user User address
     * @return organismIds Array of organism IDs
     */
    function getUserOrganisms(address user) external view returns (uint256[] memory) {
        return userOrganisms[user];
    }
    
    /**
     * @notice Initiates organism decay process
     * @param organismId Protocol organism ID
     * @return decayId Decay process ID
     */
    function initiateDecay(uint256 organismId) external returns (uint256 decayId) {
        OrganismRegistration storage reg = organismRegistry[organismId];
        if (!reg.isActive) revert OrganismNotFound();
        if (reg.owner != msg.sender) revert UnauthorizedAccess();
        
        // Update growth tracker to decay stage
        IGrowthTracker(growthTracker).updateGrowthStage(
            reg.growthTrackerId,
            IGrowthTracker.GrowthStage.DECAY
        );
        
        // Start decay process
        decayId = IDecayHandler(decayHandler).initiateDecay(reg.growthTrackerId);
        
        // Update registry
        reg.isActive = false;
        protocolStats.activeOrganisms--;
    }
    
    /**
     * @notice Updates protocol fee
     * @param newFee New fee in basis points
     */
    function updateProtocolFee(uint256 newFee) external onlyRole(FEE_MANAGER) {
        if (newFee > MAX_PROTOCOL_FEE) revert FeeExceedsMaximum();
        
        uint256 oldFee = protocolFee;
        protocolFee = newFee;
        
        emit ProtocolFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @notice Updates fee recipient
     * @param newRecipient New recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyRole(FEE_MANAGER) {
        if (newRecipient == address(0)) revert InvalidAddress();
        feeRecipient = newRecipient;
    }
    
    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(PROTOCOL_ADMIN) {
        _pause();
    }
    
    /**
     * @notice Unpause protocol
     */
    function unpause() external onlyRole(PROTOCOL_ADMIN) {
        _unpause();
    }
    
    /**
     * @notice Emergency withdrawal
     * @param token Token address (0 for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
        
        emit EmergencyWithdraw(token, amount);
    }
    
    // Internal functions
    
    function _calculateProtocolFee(uint256 baseAmount) private view returns (uint256) {
        return baseAmount + (baseAmount * protocolFee / 10000);
    }
    
    function _transferFees(uint256 amount) private {
        if (amount > 0 && feeRecipient != address(0)) {
            payable(feeRecipient).transfer(amount);
            emit FeesCollected(msg.sender, amount);
        }
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    
    // View functions for protocol statistics
    
    function getProtocolStats() external view returns (
        uint256 totalOrganisms,
        uint256 activeOrganisms,
        uint256 totalBiomassTracked,
        uint256 totalCompostGenerated,
        uint256 totalTransactions,
        uint256 totalFeesCollected
    ) {
        return (
            protocolStats.totalOrganisms,
            protocolStats.activeOrganisms,
            protocolStats.totalBiomassTracked,
            protocolStats.totalCompostGenerated,
            protocolStats.totalTransactions,
            protocolStats.totalFeesCollected
        );
    }
    
    /**
     * @notice Checks if an address is whitelisted
     * @param addr Address to check
     * @return isWhitelisted Whether the address is whitelisted
     */
    function isWhitelisted(address addr) external view returns (bool) {
        return whitelistedContracts[addr];
    }
}