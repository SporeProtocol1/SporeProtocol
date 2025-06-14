// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IGrowthTracker.sol";

/**
 * @title BioOracle
 * @author Spore Protocol
 * @notice Decentralized oracle for biological data verification
 * @dev Implements consensus mechanisms for bio-data validation
 */
contract BioOracle is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant DATA_PROVIDER_ROLE = keccak256("DATA_PROVIDER_ROLE");
    
    // Data types
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
    
    enum ValidationStatus {
        PENDING,
        VALIDATED,
        REJECTED,
        EXPIRED
    }
    
    struct DataPoint {
        uint256 organismId;
        DataType dataType;
        int256 value; // Using int256 for signed values
        uint256 timestamp;
        address provider;
        uint256 confidence; // 0-10000 (100.00%)
        ValidationStatus status;
        bytes32 proofHash;
    }
    
    struct ValidationRequest {
        bytes32 dataHash;
        uint256 dataPointId;
        uint256 requiredValidators;
        uint256 validationDeadline;
        uint256 rewardPool;
        mapping(address => bool) hasValidated;
        mapping(address => bool) validationResult;
        uint256 approvals;
        uint256 rejections;
    }
    
    struct DataFeed {
        string name;
        DataType dataType;
        address aggregator; // Chainlink aggregator if available
        uint256 heartbeat;
        int256 minValue;
        int256 maxValue;
        uint256 deviationThreshold; // Max deviation from average
        bool isActive;
    }
    
    struct ValidatorStats {
        uint256 totalValidations;
        uint256 correctValidations;
        uint256 incorrectValidations;
        uint256 reputation;
        uint256 stakedAmount;
        uint256 lastActiveBlock;
    }
    
    // Storage
    mapping(uint256 => DataPoint) public dataPoints;
    mapping(bytes32 => ValidationRequest) public validationRequests;
    mapping(bytes32 => DataFeed) public dataFeeds;
    mapping(address => ValidatorStats) public validators;
    
    // Data aggregation
    mapping(uint256 => mapping(DataType => int256[])) public historicalData;
    mapping(uint256 => mapping(DataType => int256)) public latestValues;
    
    uint256 public nextDataPointId;
    uint256 public validationReward = 0.001 ether;
    uint256 public minValidatorStake = 0.1 ether;
    uint256 public dataSubmissionFee = 0.0001 ether;
    
    IGrowthTracker public immutable growthTracker;
    
    // Events
    event DataSubmitted(
        uint256 indexed dataPointId,
        uint256 indexed organismId,
        DataType dataType,
        int256 value,
        address provider
    );
    event ValidationRequested(bytes32 indexed requestId, uint256 dataPointId, uint256 rewardPool);
    event DataValidated(uint256 indexed dataPointId, bool approved, uint256 confidence);
    event ValidatorRegistered(address indexed validator, uint256 stake);
    event ValidatorSlashed(address indexed validator, uint256 amount, string reason);
    event DataFeedCreated(bytes32 indexed feedId, string name, DataType dataType);
    event AnomalyDetected(uint256 indexed organismId, DataType dataType, int256 value, int256 expected);
    
    // Errors
    error InsufficientStake();
    error InvalidDataRange();
    error ValidationPeriodExpired();
    error AlreadyValidated();
    error InsufficientValidations();
    error DataPointNotPending();
    error InvalidConfidenceScore();
    
    modifier onlyValidator() {
        require(hasRole(VALIDATOR_ROLE, msg.sender), "Not a validator");
        require(validators[msg.sender].stakedAmount >= minValidatorStake, "Insufficient stake");
        _;
    }
    
    constructor(address _growthTracker) {
        require(_growthTracker != address(0), "Invalid growth tracker");
        growthTracker = IGrowthTracker(_growthTracker);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        
        // Initialize common data feeds
        _initializeDataFeeds();
    }
    
    /**
     * @notice Registers as a validator by staking tokens
     */
    function registerValidator() external payable {
        if (msg.value < minValidatorStake) revert InsufficientStake();
        
        validators[msg.sender].stakedAmount += msg.value;
        validators[msg.sender].reputation = 5000; // Start at 50%
        validators[msg.sender].lastActiveBlock = block.number;
        
        _grantRole(VALIDATOR_ROLE, msg.sender);
        
        emit ValidatorRegistered(msg.sender, msg.value);
    }
    
    /**
     * @notice Submits biological data for validation
     * @param organismId The organism this data belongs to
     * @param dataType Type of biological data
     * @param value The data value
     * @param proofHash Hash of supporting evidence
     * @return dataPointId The created data point ID
     */
    function submitData(
        uint256 organismId,
        DataType dataType,
        int256 value,
        bytes32 proofHash
    ) external payable onlyRole(DATA_PROVIDER_ROLE) returns (uint256 dataPointId) {
        require(msg.value >= dataSubmissionFee, "Insufficient fee");
        
        // Verify organism exists and is active
        (, , , , , , bool isActive) = growthTracker.organisms(organismId);
        require(isActive, "Organism not active");
        
        // Validate data range
        bytes32 feedId = keccak256(abi.encodePacked(dataType));
        DataFeed memory feed = dataFeeds[feedId];
        if (feed.isActive) {
            if (value < feed.minValue || value > feed.maxValue) {
                revert InvalidDataRange();
            }
        }
        
        dataPointId = nextDataPointId++;
        
        dataPoints[dataPointId] = DataPoint({
            organismId: organismId,
            dataType: dataType,
            value: value,
            timestamp: block.timestamp,
            provider: msg.sender,
            confidence: 0,
            status: ValidationStatus.PENDING,
            proofHash: proofHash
        });
        
        // Auto-validate if from trusted oracle
        if (hasRole(ORACLE_ROLE, msg.sender)) {
            dataPoints[dataPointId].status = ValidationStatus.VALIDATED;
            dataPoints[dataPointId].confidence = 10000;
            _updateLatestValue(organismId, dataType, value);
        } else {
            // Create validation request
            _createValidationRequest(dataPointId);
        }
        
        emit DataSubmitted(dataPointId, organismId, dataType, value, msg.sender);
    }
    
    /**
     * @notice Validates a submitted data point
     * @param dataPointId Data point to validate
     * @param approve Whether to approve or reject
     * @param confidence Confidence score (0-10000)
     */
    function validateData(
        uint256 dataPointId,
        bool approve,
        uint256 confidence
    ) external onlyValidator nonReentrant {
        if (confidence > 10000) revert InvalidConfidenceScore();
        
        DataPoint storage dataPoint = dataPoints[dataPointId];
        if (dataPoint.status != ValidationStatus.PENDING) revert DataPointNotPending();
        
        bytes32 requestId = keccak256(abi.encodePacked(dataPointId));
        ValidationRequest storage request = validationRequests[requestId];
        
        if (block.timestamp > request.validationDeadline) revert ValidationPeriodExpired();
        if (request.hasValidated[msg.sender]) revert AlreadyValidated();
        
        request.hasValidated[msg.sender] = true;
        request.validationResult[msg.sender] = approve;
        
        if (approve) {
            request.approvals++;
            dataPoint.confidence = (dataPoint.confidence + confidence) / 2;
        } else {
            request.rejections++;
        }
        
        validators[msg.sender].totalValidations++;
        validators[msg.sender].lastActiveBlock = block.number;
        
        // Check if validation threshold reached
        if (request.approvals >= request.requiredValidators) {
            dataPoint.status = ValidationStatus.VALIDATED;
            _updateLatestValue(dataPoint.organismId, dataPoint.dataType, dataPoint.value);
            _distributeRewards(requestId, true);
            emit DataValidated(dataPointId, true, dataPoint.confidence);
        } else if (request.rejections >= request.requiredValidators) {
            dataPoint.status = ValidationStatus.REJECTED;
            _distributeRewards(requestId, false);
            emit DataValidated(dataPointId, false, 0);
        }
    }
    
    /**
     * @notice Batch validates multiple data points
     * @param dataPointIds Array of data point IDs
     * @param approvals Array of approval decisions
     * @param confidences Array of confidence scores
     */
    function batchValidate(
        uint256[] calldata dataPointIds,
        bool[] calldata approvals,
        uint256[] calldata confidences
    ) external onlyValidator {
        require(dataPointIds.length == approvals.length && approvals.length == confidences.length, "Array mismatch");
        
        for (uint256 i = 0; i < dataPointIds.length; i++) {
            validateData(dataPointIds[i], approvals[i], confidences[i]);
        }
    }
    
    /**
     * @notice Gets aggregated data for an organism
     * @param organismId The organism to query
     * @param dataType Type of data to retrieve
     * @param numPoints Number of historical points to return
     * @return values Historical values
     * @return timestamps Corresponding timestamps
     * @return average Average value
     */
    function getAggregatedData(
        uint256 organismId,
        DataType dataType,
        uint256 numPoints
    ) external view returns (
        int256[] memory values,
        uint256[] memory timestamps,
        int256 average
    ) {
        int256[] storage history = historicalData[organismId][dataType];
        uint256 pointsToReturn = history.length < numPoints ? history.length : numPoints;
        
        values = new int256[](pointsToReturn);
        timestamps = new uint256[](pointsToReturn);
        
        int256 sum = 0;
        uint256 startIdx = history.length > pointsToReturn ? history.length - pointsToReturn : 0;
        
        for (uint256 i = 0; i < pointsToReturn; i++) {
            values[i] = history[startIdx + i];
            sum += values[i];
        }
        
        average = pointsToReturn > 0 ? sum / int256(pointsToReturn) : 0;
    }
    
    /**
     * @notice Checks if data point represents an anomaly
     * @param dataPointId Data point to check
     * @return isAnomaly Whether the data is anomalous
     * @return deviation Percentage deviation from expected
     */
    function checkAnomaly(uint256 dataPointId) external view returns (bool isAnomaly, uint256 deviation) {
        DataPoint memory dataPoint = dataPoints[dataPointId];
        
        int256[] memory history = historicalData[dataPoint.organismId][dataPoint.dataType];
        if (history.length < 10) return (false, 0); // Need sufficient history
        
        // Calculate moving average of last 10 points
        int256 sum = 0;
        uint256 startIdx = history.length - 10;
        for (uint256 i = startIdx; i < history.length; i++) {
            sum += history[i];
        }
        int256 movingAvg = sum / 10;
        
        // Calculate deviation
        int256 diff = dataPoint.value > movingAvg ? dataPoint.value - movingAvg : movingAvg - dataPoint.value;
        deviation = uint256((diff * 10000) / (movingAvg > 0 ? movingAvg : 1));
        
        bytes32 feedId = keccak256(abi.encodePacked(dataPoint.dataType));
        DataFeed memory feed = dataFeeds[feedId];
        
        isAnomaly = deviation > feed.deviationThreshold;
        
        if (isAnomaly) {
            emit AnomalyDetected(dataPoint.organismId, dataPoint.dataType, dataPoint.value, movingAvg);
        }
    }
    
    /**
     * @notice Creates a data feed configuration
     * @param name Feed name
     * @param dataType Type of data
     * @param minValue Minimum valid value
     * @param maxValue Maximum valid value
     * @param deviationThreshold Max allowed deviation
     * @param aggregator Chainlink aggregator address (optional)
     */
    function createDataFeed(
        string memory name,
        DataType dataType,
        int256 minValue,
        int256 maxValue,
        uint256 deviationThreshold,
        address aggregator
    ) external onlyRole(ORACLE_ROLE) {
        bytes32 feedId = keccak256(abi.encodePacked(dataType));
        
        dataFeeds[feedId] = DataFeed({
            name: name,
            dataType: dataType,
            aggregator: aggregator,
            heartbeat: 3600, // 1 hour default
            minValue: minValue,
            maxValue: maxValue,
            deviationThreshold: deviationThreshold,
            isActive: true
        });
        
        emit DataFeedCreated(feedId, name, dataType);
    }
    
    /**
     * @notice Gets latest validated value for organism
     * @param organismId The organism to query
     * @param dataType Type of data
     * @return value Latest value
     * @return timestamp When it was recorded
     * @return confidence Confidence score
     */
    function getLatestValue(
        uint256 organismId,
        DataType dataType
    ) external view returns (int256 value, uint256 timestamp, uint256 confidence) {
        // First check Chainlink feed if available
        bytes32 feedId = keccak256(abi.encodePacked(dataType));
        DataFeed memory feed = dataFeeds[feedId];
        
        if (feed.aggregator != address(0)) {
            try AggregatorV3Interface(feed.aggregator).latestRoundData() returns (
                uint80,
                int256 price,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                return (price, updatedAt, 10000); // Chainlink data has max confidence
            } catch {
                // Fall back to internal data
            }
        }
        
        // Return latest internal value
        value = latestValues[organismId][dataType];
        
        // Find most recent validated data point
        for (uint256 i = nextDataPointId; i > 0; i--) {
            DataPoint memory dp = dataPoints[i - 1];
            if (dp.organismId == organismId && 
                dp.dataType == dataType && 
                dp.status == ValidationStatus.VALIDATED) {
                return (dp.value, dp.timestamp, dp.confidence);
            }
        }
        
        return (0, 0, 0);
    }
    
    /**
     * @notice Slashes a validator for malicious behavior
     * @param validator Address to slash
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slashValidator(
        address validator,
        uint256 amount,
        string memory reason
    ) external onlyRole(ORACLE_ROLE) {
        ValidatorStats storage stats = validators[validator];
        require(stats.stakedAmount >= amount, "Insufficient stake to slash");
        
        stats.stakedAmount -= amount;
        stats.reputation = stats.reputation > 1000 ? stats.reputation - 1000 : 0;
        stats.incorrectValidations++;
        
        // Remove validator role if stake below minimum
        if (stats.stakedAmount < minValidatorStake) {
            _revokeRole(VALIDATOR_ROLE, validator);
        }
        
        emit ValidatorSlashed(validator, amount, reason);
    }
    
    /**
     * @notice Withdraws validator stake
     * @param amount Amount to withdraw
     */
    function withdrawStake(uint256 amount) external {
        ValidatorStats storage stats = validators[msg.sender];
        require(stats.stakedAmount >= amount, "Insufficient stake");
        require(block.number > stats.lastActiveBlock + 28800, "Must wait 1 day after last validation");
        
        stats.stakedAmount -= amount;
        
        if (stats.stakedAmount < minValidatorStake) {
            _revokeRole(VALIDATOR_ROLE, msg.sender);
        }
        
        payable(msg.sender).transfer(amount);
    }
    
    // Internal functions
    
    function _initializeDataFeeds() private {
        // Temperature: -50°C to 100°C
        _createDataFeed("Temperature", DataType.TEMPERATURE, -50 * 100, 100 * 100, 2000);
        
        // Humidity: 0-100%
        _createDataFeed("Humidity", DataType.HUMIDITY, 0, 10000, 1500);
        
        // pH: 0-14 (scaled by 100)
        _createDataFeed("pH Level", DataType.PH_LEVEL, 0, 1400, 1000);
        
        // Light: 0-100000 lux
        _createDataFeed("Light Intensity", DataType.LIGHT_INTENSITY, 0, 100000, 3000);
        
        // CO2: 0-5000 ppm
        _createDataFeed("CO2 Level", DataType.CO2_LEVEL, 0, 5000, 2500);
    }
    
    function _createDataFeed(
        string memory name,
        DataType dataType,
        int256 minValue,
        int256 maxValue,
        uint256 deviationThreshold
    ) private {
        bytes32 feedId = keccak256(abi.encodePacked(dataType));
        
        dataFeeds[feedId] = DataFeed({
            name: name,
            dataType: dataType,
            aggregator: address(0),
            heartbeat: 3600,
            minValue: minValue,
            maxValue: maxValue,
            deviationThreshold: deviationThreshold,
            isActive: true
        });
    }
    
    function _createValidationRequest(uint256 dataPointId) private {
        bytes32 requestId = keccak256(abi.encodePacked(dataPointId));
        
        ValidationRequest storage request = validationRequests[requestId];
        request.dataHash = keccak256(abi.encodePacked(dataPoints[dataPointId].value));
        request.dataPointId = dataPointId;
        request.requiredValidators = 3; // Require 3 validators
        request.validationDeadline = block.timestamp + 1 hours;
        request.rewardPool = msg.value;
        
        emit ValidationRequested(requestId, dataPointId, msg.value);
    }
    
    function _updateLatestValue(uint256 organismId, DataType dataType, int256 value) private {
        latestValues[organismId][dataType] = value;
        historicalData[organismId][dataType].push(value);
        
        // Keep only last 100 data points
        if (historicalData[organismId][dataType].length > 100) {
            // In production, implement proper array management
        }
    }
    
    function _distributeRewards(bytes32 requestId, bool approved) private {
        ValidationRequest storage request = validationRequests[requestId];
        uint256 rewardPerValidator = request.rewardPool / request.requiredValidators;
        
        // Distribute to validators who voted with majority
        // Implementation simplified for example
    }
    
    // Admin functions
    
    function updateValidationReward(uint256 newReward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validationReward = newReward;
    }
    
    function updateMinValidatorStake(uint256 newStake) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minValidatorStake = newStake;
    }
    
    function grantDataProviderRole(address provider) external onlyRole(ORACLE_ROLE) {
        _grantRole(DATA_PROVIDER_ROLE, provider);
    }
}