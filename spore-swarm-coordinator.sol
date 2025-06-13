// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SwarmCoordinator
 * @author Spore Protocol
 * @notice Implements decentralized swarm intelligence for multi-robot coordination
 * @dev Uses consensus mechanisms for task allocation and swarm behavior
 */
contract SwarmCoordinator is AccessControl, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using ECDSA for bytes32;
    
    bytes32 public constant SWARM_OPERATOR = keccak256("SWARM_OPERATOR");
    bytes32 public constant ROBOT_ROLE = keccak256("ROBOT_ROLE");
    
    // Swarm behavior modes
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
    
    // Task priorities
    enum Priority {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }
    
    struct Robot {
        address controller;
        uint256 x;
        uint256 y;
        uint256 z;
        uint256 battery; // 0-10000 (100.00%)
        uint256 capacity;
        bool isActive;
        uint256 currentTaskId;
        uint256 reputation; // Performance score
    }
    
    struct Swarm {
        string name;
        SwarmMode mode;
        EnumerableSet.UintSet robotIds;
        uint256 createdAt;
        bool isActive;
        bytes32 consensusRules; // Hash of consensus algorithm
        uint256 minRobots;
        uint256 maxRobots;
    }
    
    struct Task {
        string description;
        uint256 swarmId;
        Priority priority;
        uint256 reward;
        uint256 deadline;
        uint256 minRobots;
        uint256 completionThreshold; // % of robots that must confirm completion
        EnumerableSet.UintSet assignedRobots;
        EnumerableSet.AddressSet completionVotes;
        bool isCompleted;
        bytes metadata;
    }
    
    struct ConsensusVote {
        uint256 proposalId;
        bytes32 dataHash;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 deadline;
        mapping(uint256 => bool) hasVoted;
    }
    
    // Storage
    uint256 public nextRobotId;
    uint256 public nextSwarmId;
    uint256 public nextTaskId;
    uint256 public nextProposalId;
    
    mapping(uint256 => Robot) public robots;
    mapping(uint256 => Swarm) private swarms;
    mapping(uint256 => Task) private tasks;
    mapping(uint256 => ConsensusVote) public consensusVotes;
    
    // Robot coordination
    mapping(uint256 => mapping(uint256 => uint256)) public pheromoneTrails; // For ant-colony optimization
    mapping(uint256 => uint256) public robotSwarmAssignment;
    mapping(address => uint256) public controllerToRobot;
    
    // Task metrics
    mapping(uint256 => uint256) public taskCompletionTimes;
    mapping(uint256 => uint256) public swarmEfficiencyScore;
    
    // Events
    event RobotRegistered(uint256 indexed robotId, address indexed controller);
    event SwarmCreated(uint256 indexed swarmId, string name, SwarmMode mode);
    event RobotJoinedSwarm(uint256 indexed robotId, uint256 indexed swarmId);
    event TaskCreated(uint256 indexed taskId, uint256 indexed swarmId, Priority priority);
    event TaskAssigned(uint256 indexed taskId, uint256 indexed robotId);
    event TaskCompleted(uint256 indexed taskId, uint256 completionTime);
    event SwarmModeChanged(uint256 indexed swarmId, SwarmMode oldMode, SwarmMode newMode);
    event ConsensusReached(uint256 indexed proposalId, bool approved);
    event PheromoneUpdated(uint256 indexed robotId, uint256 indexed targetId, uint256 strength);
    
    // Errors
    error RobotNotActive();
    error SwarmNotActive();
    error SwarmFull();
    error InsufficientRobots();
    error TaskExpired();
    error AlreadyVoted();
    error NotSwarmMember();
    error InvalidPosition();
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SWARM_OPERATOR, msg.sender);
    }
    
    /**
     * @notice Registers a new robot in the system
     * @param controller Address controlling the robot
     * @param x Initial X coordinate
     * @param y Initial Y coordinate
     * @param capacity Robot's cargo capacity
     * @return robotId The assigned robot ID
     */
    function registerRobot(
        address controller,
        uint256 x,
        uint256 y,
        uint256 capacity
    ) external onlyRole(SWARM_OPERATOR) returns (uint256 robotId) {
        robotId = nextRobotId++;
        
        robots[robotId] = Robot({
            controller: controller,
            x: x,
            y: y,
            z: 0,
            battery: 10000,
            capacity: capacity,
            isActive: true,
            currentTaskId: 0,
            reputation: 5000 // Start at 50%
        });
        
        controllerToRobot[controller] = robotId;
        _grantRole(ROBOT_ROLE, controller);
        
        emit RobotRegistered(robotId, controller);
    }
    
    /**
     * @notice Creates a new swarm with specified parameters
     * @param name Swarm identifier
     * @param mode Initial swarm behavior mode
     * @param minRobots Minimum robots required
     * @param maxRobots Maximum robots allowed
     * @param consensusRules Hash of consensus algorithm
     * @return swarmId The created swarm ID
     */
    function createSwarm(
        string memory name,
        SwarmMode mode,
        uint256 minRobots,
        uint256 maxRobots,
        bytes32 consensusRules
    ) external onlyRole(SWARM_OPERATOR) returns (uint256 swarmId) {
        require(maxRobots >= minRobots, "Invalid robot limits");
        
        swarmId = nextSwarmId++;
        
        Swarm storage swarm = swarms[swarmId];
        swarm.name = name;
        swarm.mode = mode;
        swarm.createdAt = block.timestamp;
        swarm.isActive = true;
        swarm.consensusRules = consensusRules;
        swarm.minRobots = minRobots;
        swarm.maxRobots = maxRobots;
        
        emit SwarmCreated(swarmId, name, mode);
    }
    
    /**
     * @notice Assigns a robot to a swarm
     * @param robotId Robot to assign
     * @param swarmId Target swarm
     */
    function joinSwarm(uint256 robotId, uint256 swarmId) external {
        Robot storage robot = robots[robotId];
        require(msg.sender == robot.controller || hasRole(SWARM_OPERATOR, msg.sender), "Unauthorized");
        
        if (!robot.isActive) revert RobotNotActive();
        
        Swarm storage swarm = swarms[swarmId];
        if (!swarm.isActive) revert SwarmNotActive();
        if (swarm.robotIds.length() >= swarm.maxRobots) revert SwarmFull();
        
        // Remove from previous swarm if any
        uint256 previousSwarm = robotSwarmAssignment[robotId];
        if (previousSwarm != 0) {
            swarms[previousSwarm].robotIds.remove(robotId);
        }
        
        swarm.robotIds.add(robotId);
        robotSwarmAssignment[robotId] = swarmId;
        
        emit RobotJoinedSwarm(robotId, swarmId);
    }
    
    /**
     * @notice Creates a task for a swarm to execute
     * @param description Task description
     * @param swarmId Target swarm
     * @param priority Task priority
     * @param reward Reward amount
     * @param duration Task duration in seconds
     * @param minRobots Minimum robots required
     * @param metadata Additional task data
     * @return taskId Created task ID
     */
    function createTask(
        string memory description,
        uint256 swarmId,
        Priority priority,
        uint256 reward,
        uint256 duration,
        uint256 minRobots,
        bytes memory metadata
    ) external onlyRole(SWARM_OPERATOR) returns (uint256 taskId) {
        Swarm storage swarm = swarms[swarmId];
        if (!swarm.isActive) revert SwarmNotActive();
        if (swarm.robotIds.length() < minRobots) revert InsufficientRobots();
        
        taskId = nextTaskId++;
        
        Task storage task = tasks[taskId];
        task.description = description;
        task.swarmId = swarmId;
        task.priority = priority;
        task.reward = reward;
        task.deadline = block.timestamp + duration;
        task.minRobots = minRobots;
        task.completionThreshold = 66; // 66% must confirm completion
        task.metadata = metadata;
        
        emit TaskCreated(taskId, swarmId, priority);
        
        // Auto-assign based on swarm mode
        _assignTaskToSwarm(taskId, swarmId);
    }
    
    /**
     * @notice Updates robot position and state
     * @param x New X coordinate
     * @param y New Y coordinate
     * @param z New Z coordinate
     * @param battery Current battery level
     */
    function updateRobotState(
        uint256 x,
        uint256 y,
        uint256 z,
        uint256 battery
    ) external onlyRole(ROBOT_ROLE) {
        uint256 robotId = controllerToRobot[msg.sender];
        Robot storage robot = robots[robotId];
        
        if (!robot.isActive) revert RobotNotActive();
        
        // Validate position (basic bounds check)
        if (x > 1000000 || y > 1000000 || z > 1000000) revert InvalidPosition();
        
        robot.x = x;
        robot.y = y;
        robot.z = z;
        robot.battery = battery;
    }
    
    /**
     * @notice Submits task completion vote
     * @param taskId Task to mark as complete
     */
    function voteTaskCompletion(uint256 taskId) external onlyRole(ROBOT_ROLE) {
        Task storage task = tasks[taskId];
        require(!task.isCompleted, "Task already completed");
        require(block.timestamp <= task.deadline, "Task expired");
        
        uint256 robotId = controllerToRobot[msg.sender];
        require(task.assignedRobots.contains(robotId), "Not assigned to task");
        
        task.completionVotes.add(msg.sender);
        
        // Check if threshold reached
        uint256 votesNeeded = (task.assignedRobots.length() * task.completionThreshold) / 100;
        if (task.completionVotes.length() >= votesNeeded) {
            task.isCompleted = true;
            taskCompletionTimes[taskId] = block.timestamp;
            
            // Update robot reputation
            uint256[] memory assignedRobots = task.assignedRobots.values();
            for (uint256 i = 0; i < assignedRobots.length; i++) {
                robots[assignedRobots[i]].reputation += 100; // Increase reputation
            }
            
            // Update swarm efficiency
            uint256 efficiency = _calculateEfficiency(taskId);
            swarmEfficiencyScore[task.swarmId] = 
                (swarmEfficiencyScore[task.swarmId] * 9 + efficiency) / 10; // Moving average
            
            emit TaskCompleted(taskId, block.timestamp);
        }
    }
    
    /**
     * @notice Updates pheromone trail strength between robots
     * @param targetRobotId Target robot
     * @param strength Pheromone strength (0-10000)
     */
    function updatePheromone(uint256 targetRobotId, uint256 strength) external onlyRole(ROBOT_ROLE) {
        uint256 robotId = controllerToRobot[msg.sender];
        require(robots[robotId].isActive && robots[targetRobotId].isActive, "Invalid robots");
        require(strength <= 10000, "Invalid strength");
        
        pheromoneTrails[robotId][targetRobotId] = strength;
        emit PheromoneUpdated(robotId, targetRobotId, strength);
    }
    
    /**
     * @notice Proposes a swarm behavior change requiring consensus
     * @param swarmId Target swarm
     * @param newMode Proposed new mode
     * @param dataHash Hash of supporting data
     * @return proposalId Created proposal ID
     */
    function proposeSwarmModeChange(
        uint256 swarmId,
        SwarmMode newMode,
        bytes32 dataHash
    ) external onlyRole(ROBOT_ROLE) returns (uint256 proposalId) {
        uint256 robotId = controllerToRobot[msg.sender];
        if (robotSwarmAssignment[robotId] != swarmId) revert NotSwarmMember();
        
        proposalId = nextProposalId++;
        
        ConsensusVote storage vote = consensusVotes[proposalId];
        vote.proposalId = proposalId;
        vote.dataHash = dataHash;
        vote.deadline = block.timestamp + 1 hours;
        
        // Store new mode in dataHash for retrieval
        // First vote counts as 'for'
        vote.forVotes = 1;
        vote.hasVoted[robotId] = true;
    }
    
    /**
     * @notice Votes on a consensus proposal
     * @param proposalId Proposal to vote on
     * @param support True for yes, false for no
     */
    function voteOnProposal(uint256 proposalId, bool support) external onlyRole(ROBOT_ROLE) {
        ConsensusVote storage vote = consensusVotes[proposalId];
        require(block.timestamp <= vote.deadline, "Voting ended");
        
        uint256 robotId = controllerToRobot[msg.sender];
        if (vote.hasVoted[robotId]) revert AlreadyVoted();
        
        vote.hasVoted[robotId] = true;
        
        if (support) {
            vote.forVotes++;
        } else {
            vote.againstVotes++;
        }
        
        // Check if consensus reached (simple majority)
        uint256 totalVotes = vote.forVotes + vote.againstVotes;
        uint256 swarmSize = _getSwarmSizeForRobot(robotId);
        
        if (totalVotes >= (swarmSize * 2) / 3) { // 66% participation
            bool approved = vote.forVotes > vote.againstVotes;
            emit ConsensusReached(proposalId, approved);
            
            if (approved) {
                // Execute the proposal (simplified for this example)
                _executeProposal(proposalId);
            }
        }
    }
    
    /**
     * @notice Calculates optimal task distribution using swarm intelligence
     * @param swarmId Swarm to optimize
     * @return distribution Optimal robot-task mapping
     */
    function calculateOptimalDistribution(uint256 swarmId) external view returns (
        uint256[] memory robotIds,
        uint256[] memory taskIds,
        uint256[] memory assignments
    ) {
        Swarm storage swarm = swarms[swarmId];
        uint256[] memory swarmRobots = swarm.robotIds.values();
        
        // Get active tasks for swarm
        uint256 activeTaskCount = 0;
        for (uint256 i = 1; i < nextTaskId; i++) {
            if (tasks[i].swarmId == swarmId && !tasks[i].isCompleted && 
                block.timestamp <= tasks[i].deadline) {
                activeTaskCount++;
            }
        }
        
        robotIds = new uint256[](swarmRobots.length);
        taskIds = new uint256[](activeTaskCount);
        assignments = new uint256[](swarmRobots.length);
        
        // Simple round-robin assignment (in production, use more sophisticated algorithms)
        uint256 taskIndex = 0;
        for (uint256 i = 1; i < nextTaskId && taskIndex < activeTaskCount; i++) {
            Task storage task = tasks[i];
            if (task.swarmId == swarmId && !task.isCompleted && 
                block.timestamp <= task.deadline) {
                taskIds[taskIndex] = i;
                
                // Assign robots based on reputation and battery
                for (uint256 j = 0; j < swarmRobots.length; j++) {
                    Robot storage robot = robots[swarmRobots[j]];
                    if (robot.battery > 2000 && robot.currentTaskId == 0) {
                        robotIds[j] = swarmRobots[j];
                        assignments[j] = i;
                        break;
                    }
                }
                taskIndex++;
            }
        }
    }
    
    /**
     * @notice Emergency stop for a swarm
     * @param swarmId Swarm to stop
     */
    function emergencyStop(uint256 swarmId) external onlyRole(SWARM_OPERATOR) {
        Swarm storage swarm = swarms[swarmId];
        swarm.mode = SwarmMode.IDLE;
        
        // Clear all robot tasks
        uint256[] memory swarmRobots = swarm.robotIds.values();
        for (uint256 i = 0; i < swarmRobots.length; i++) {
            robots[swarmRobots[i]].currentTaskId = 0;
        }
        
        emit SwarmModeChanged(swarmId, swarm.mode, SwarmMode.IDLE);
    }
    
    // Internal functions
    
    function _assignTaskToSwarm(uint256 taskId, uint256 swarmId) private {
        Swarm storage swarm = swarms[swarmId];
        Task storage task = tasks[taskId];
        
        uint256[] memory swarmRobots = swarm.robotIds.values();
        uint256 assigned = 0;
        
        // Assign based on swarm mode and robot availability
        for (uint256 i = 0; i < swarmRobots.length && assigned < task.minRobots; i++) {
            Robot storage robot = robots[swarmRobots[i]];
            
            if (robot.isActive && robot.battery > 2000 && robot.currentTaskId == 0) {
                task.assignedRobots.add(swarmRobots[i]);
                robot.currentTaskId = taskId;
                assigned++;
                
                emit TaskAssigned(taskId, swarmRobots[i]);
            }
        }
        
        require(assigned >= task.minRobots, "Could not assign enough robots");
    }
    
    function _calculateEfficiency(uint256 taskId) private view returns (uint256) {
        Task storage task = tasks[taskId];
        uint256 completionTime = taskCompletionTimes[taskId] - (task.deadline - 3600); // Task created 1h before deadline
        uint256 expectedTime = 3600; // 1 hour expected
        
        if (completionTime <= expectedTime) {
            return 10000; // 100% efficiency
        } else {
            return (expectedTime * 10000) / completionTime;
        }
    }
    
    function _getSwarmSizeForRobot(uint256 robotId) private view returns (uint256) {
        uint256 swarmId = robotSwarmAssignment[robotId];
        if (swarmId == 0) return 0;
        return swarms[swarmId].robotIds.length();
    }
    
    function _executeProposal(uint256 proposalId) private {
        // Implementation depends on proposal type
        // For mode changes, extract from dataHash and apply
    }
    
    // View functions for swarm data
    
    function getSwarmRobots(uint256 swarmId) external view returns (uint256[] memory) {
        return swarms[swarmId].robotIds.values();
    }
    
    function getTaskAssignedRobots(uint256 taskId) external view returns (uint256[] memory) {
        return tasks[taskId].assignedRobots.values();
    }
    
    function getSwarmInfo(uint256 swarmId) external view returns (
        string memory name,
        SwarmMode mode,
        uint256 robotCount,
        bool isActive,
        uint256 efficiency
    ) {
        Swarm storage swarm = swarms[swarmId];
        return (
            swarm.name,
            swarm.mode,
            swarm.robotIds.length(),
            swarm.isActive,
            swarmEfficiencyScore[swarmId]
        );
    }
}