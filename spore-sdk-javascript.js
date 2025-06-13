// Spore Protocol JavaScript SDK
// Comprehensive SDK for interacting with Spore Protocol

import { ethers } from 'ethers';
import axios from 'axios';
import WebSocket from 'isomorphic-ws';
import EventEmitter from 'events';

// ABIs (simplified for example)
const GROWTH_TRACKER_ABI = [
  "function createOrganism(uint256 species, uint64 initialBiomass, uint16 growthRate) returns (uint256)",
  "function updateGrowthStage(uint256 organismId, uint8 newStage)",
  "function organisms(uint256) view returns (tuple(uint128 birthBlock, uint64 currentStage, uint64 biomass, uint128 lastUpdateBlock, uint16 healthScore, uint16 growthRate, bool isActive))",
  "event OrganismCreated(uint256 indexed organismId, address indexed creator, uint256 species)"
];

const BIO_NFT_ABI = [
  "function mintBioNFT(address to, string species, uint256 growthTrackerId, uint256[2] parentIds) returns (uint256)",
  "function breed(uint256 parentTokenId1, uint256 parentTokenId2, uint256 growthTrackerId) returns (uint256)",
  "function getOrganismData(uint256 tokenId) view returns (tuple(string species, uint256 stage, uint256 health, uint256 biomass, tuple(uint16 growthSpeed, uint16 diseaseResistance, uint16 yieldPotential, uint16 adaptability, uint8 generation, uint8 rarity) genetics))"
];

const REGISTRY_ABI = [
  "function registerOrganism(string species, uint64 initialBiomass, uint16 growthRate, bytes metadata) payable returns (uint256)",
  "function getOrganismData(uint256 organismId) view returns (tuple(uint256 growthTrackerId, uint256 bioNFTId, address owner, uint256 registrationBlock, bool isActive, string species, bytes metadata) registration, uint256 currentStage, uint256 health, uint256 biomass, tuple(uint16 growthSpeed, uint16 diseaseResistance, uint16 yieldPotential, uint16 adaptability, uint8 generation, uint8 rarity) genetics)"
];

// Constants
const DEFAULT_SIMULATOR_URL = 'https://api.sporeprotocol.io';
const DEFAULT_WS_URL = 'wss://stream.sporeprotocol.io';

// Growth stages enum
const GrowthStage = {
  SEED: 0,
  GERMINATION: 1,
  VEGETATIVE: 2,
  FLOWERING: 3,
  FRUITING: 4,
  HARVEST: 5,
  DECAY: 6
};

// Data types for bio oracle
const DataType = {
  TEMPERATURE: 0,
  HUMIDITY: 1,
  PH_LEVEL: 2,
  LIGHT_INTENSITY: 3,
  CO2_LEVEL: 4,
  NUTRIENT_CONCENTRATION: 5,
  GROWTH_RATE: 6,
  BIOMASS: 7,
  HEALTH_SCORE: 8,
  ELECTRICAL_SIGNAL: 9
};

/**
 * Main SporeSDK class
 */
class SporeSDK extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.config = {
      simulatorUrl: config.simulatorUrl || DEFAULT_SIMULATOR_URL,
      wsUrl: config.wsUrl || DEFAULT_WS_URL,
      apiKey: config.apiKey,
      network: config.network || 'mainnet',
      contractAddresses: config.contractAddresses || this._getDefaultAddresses(config.network),
      provider: config.provider,
      signer: config.signer
    };
    
    this.contracts = {};
    this.simulatorClient = this._createSimulatorClient();
    this.wsConnections = new Map();
    
    if (this.config.provider) {
      this._initializeContracts();
    }
  }
  
  /**
   * Initialize blockchain connection
   */
  async connect(providerOrSigner) {
    if (typeof providerOrSigner === 'string') {
      // RPC URL provided
      this.config.provider = new ethers.JsonRpcProvider(providerOrSigner);
    } else if (providerOrSigner._isSigner) {
      // Signer provided
      this.config.signer = providerOrSigner;
      this.config.provider = providerOrSigner.provider;
    } else {
      // Provider provided
      this.config.provider = providerOrSigner;
    }
    
    this._initializeContracts();
    
    const network = await this.config.provider.getNetwork();
    this.emit('connected', { chainId: network.chainId });
    
    return this;
  }
  
  /**
   * Connect wallet (browser environment)
   */
  async connectWallet() {
    if (typeof window === 'undefined' || !window.ethereum) {
      throw new Error('No web3 wallet detected');
    }
    
    await window.ethereum.request({ method: 'eth_requestAccounts' });
    
    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();
    
    this.config.provider = provider;
    this.config.signer = signer;
    
    this._initializeContracts();
    
    const address = await signer.getAddress();
    const network = await provider.getNetwork();
    
    this.emit('walletConnected', { address, chainId: network.chainId });
    
    return { address, chainId: network.chainId };
  }
  
  /**
   * Create a new organism
   */
  async createOrganism(params) {
    const {
      species,
      initialBiomass = 100,
      growthRate = 50,
      metadata = '',
      simulate = true
    } = params;
    
    // Create on blockchain if connected
    let blockchainData = null;
    if (this.contracts.registry && this.config.signer) {
      const tx = await this.contracts.registry.registerOrganism(
        species,
        initialBiomass,
        growthRate,
        ethers.toUtf8Bytes(metadata),
        { value: ethers.parseEther('0.01') } // Registration fee
      );
      
      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.topics[0] === ethers.id('OrganismRegistered(uint256,address,string)')
      );
      
      blockchainData = {
        organismId: event.args[0],
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber
      };
    }
    
    // Create in simulator if requested
    let simulatorData = null;
    if (simulate) {
      const response = await this.simulatorClient.post('/organisms', {
        species,
        initialBiomass
      });
      
      simulatorData = response.data.organism;
    }
    
    return {
      blockchain: blockchainData,
      simulator: simulatorData,
      species,
      initialBiomass,
      growthRate
    };
  }
  
  /**
   * Get organism data
   */
  async getOrganism(organismId, options = {}) {
    const { includeSimulation = true, includeBlockchain = true } = options;
    
    const result = {};
    
    // Get blockchain data
    if (includeBlockchain && this.contracts.registry) {
      const data = await this.contracts.registry.getOrganismData(organismId);
      result.blockchain = {
        registration: data.registration,
        currentStage: Number(data.currentStage),
        health: Number(data.health),
        biomass: Number(data.biomass),
        genetics: data.genetics
      };
    }
    
    // Get simulator data
    if (includeSimulation && result.blockchain?.registration?.species) {
      try {
        const response = await this.simulatorClient.get(`/organisms/${organismId}`);
        result.simulator = response.data;
      } catch (error) {
        // Organism might not exist in simulator
        result.simulator = null;
      }
    }
    
    return result;
  }
  
  /**
   * Stream real-time organism data
   */
  streamOrganism(organismId, callbacks = {}) {
    const ws = new WebSocket(`${this.config.wsUrl}?organismId=${organismId}`);
    
    ws.on('open', () => {
      this.emit('streamConnected', { organismId });
      if (callbacks.onConnect) callbacks.onConnect();
    });
    
    ws.on('message', (data) => {
      const message = JSON.parse(data);
      
      switch (message.type) {
        case 'initial':
          if (callbacks.onInitial) callbacks.onInitial(message.data);
          break;
        case 'update':
          if (callbacks.onUpdate) callbacks.onUpdate(message.data);
          this.emit('organismUpdate', { organismId, data: message.data });
          break;
        case 'error':
          if (callbacks.onError) callbacks.onError(message.message);
          break;
      }
    });
    
    ws.on('close', () => {
      this.wsConnections.delete(organismId);
      this.emit('streamDisconnected', { organismId });
      if (callbacks.onDisconnect) callbacks.onDisconnect();
    });
    
    ws.on('error', (error) => {
      if (callbacks.onError) callbacks.onError(error);
      this.emit('streamError', { organismId, error });
    });
    
    // Store connection
    this.wsConnections.set(organismId, ws);
    
    // Return control object
    return {
      updateEnvironment: (factors) => {
        ws.send(JSON.stringify({
          action: 'updateEnvironment',
          data: factors
        }));
      },
      close: () => {
        ws.close();
        this.wsConnections.delete(organismId);
      }
    };
  }
  
  /**
   * Update organism growth stage
   */
  async updateGrowthStage(organismId, newStage) {
    if (!this.contracts.growthTracker || !this.config.signer) {
      throw new Error('Blockchain connection required');
    }
    
    const tx = await this.contracts.growthTracker.updateGrowthStage(
      organismId,
      newStage
    );
    
    const receipt = await tx.wait();
    
    return {
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber
    };
  }
  
  /**
   * Submit biological data
   */
  async submitBioData(params) {
    const { organismId, dataType, value, confidence = 100 } = params;
    
    // Submit to simulator
    const simulatorResponse = await this.simulatorClient.put(
      `/organisms/${organismId}`,
      {
        environmentalFactors: {
          [this._dataTypeToField(dataType)]: value
        }
      }
    );
    
    // Submit to blockchain if available
    let blockchainResponse = null;
    if (this.contracts.bioOracle && this.config.signer) {
      const tx = await this.contracts.bioOracle.submitData(
        organismId,
        dataType,
        value,
        ethers.keccak256(ethers.toUtf8Bytes(`${Date.now()}`)),
        { value: ethers.parseEther('0.0001') }
      );
      
      const receipt = await tx.wait();
      blockchainResponse = {
        txHash: receipt.hash,
        dataPointId: receipt.logs[0].args[0]
      };
    }
    
    return {
      simulator: simulatorResponse.data,
      blockchain: blockchainResponse
    };
  }
  
  /**
   * Predict organism growth
   */
  async predictGrowth(organismId, hours = 24) {
    const response = await this.simulatorClient.post(
      `/data/${organismId}/predict`,
      { hours }
    );
    
    return response.data;
  }
  
  /**
   * Get historical data
   */
  async getHistoricalData(organismId, options = {}) {
    const response = await this.simulatorClient.get(
      `/data/${organismId}/historical`,
      { params: options }
    );
    
    return response.data;
  }
  
  /**
   * Allocate resources to organism
   */
  async allocateResources(organismId, resources) {
    if (!this.contracts.resourcePool || !this.config.signer) {
      throw new Error('Blockchain connection required');
    }
    
    const transactions = [];
    
    for (const [resourceType, amount] of Object.entries(resources)) {
      const tx = await this.contracts.resourcePool.allocateResource(
        organismId,
        ethers.id(resourceType.toUpperCase()),
        amount,
        50 // Default priority
      );
      
      transactions.push(tx.wait());
    }
    
    const receipts = await Promise.all(transactions);
    
    return receipts.map(r => ({
      txHash: r.hash,
      blockNumber: r.blockNumber
    }));
  }
  
  /**
   * Breed two organisms
   */
  async breedOrganisms(parentId1, parentId2) {
    if (!this.contracts.bioNFT || !this.config.signer) {
      throw new Error('Blockchain connection required');
    }
    
    // Create new organism in growth tracker first
    const parent1Data = await this.getOrganism(parentId1);
    const species = parent1Data.blockchain.registration.species;
    
    const growthTx = await this.contracts.growthTracker.createOrganism(
      ethers.id(species),
      50, // Initial biomass for offspring
      45  // Growth rate
    );
    
    const growthReceipt = await growthTx.wait();
    const growthTrackerId = growthReceipt.logs[0].args[0];
    
    // Breed NFTs
    const breedTx = await this.contracts.bioNFT.breed(
      parentId1,
      parentId2,
      growthTrackerId
    );
    
    const breedReceipt = await breedTx.wait();
    const offspringTokenId = breedReceipt.logs[0].args[0];
    
    return {
      offspringId: offspringTokenId,
      growthTrackerId,
      parents: [parentId1, parentId2],
      txHash: breedReceipt.hash
    };
  }
  
  /**
   * Trigger chaos event (simulator only)
   */
  async triggerChaosEvent(organismId, eventType) {
    const response = await this.simulatorClient.post('/chaos/trigger', {
      organismId,
      event: eventType
    });
    
    return response.data;
  }
  
  /**
   * Batch operations
   */
  async batchOperation(operations) {
    const results = [];
    
    for (const op of operations) {
      try {
        let result;
        
        switch (op.type) {
          case 'create':
            result = await this.createOrganism(op.params);
            break;
          case 'update':
            result = await this.updateGrowthStage(op.organismId, op.stage);
            break;
          case 'submitData':
            result = await this.submitBioData(op.params);
            break;
          default:
            throw new Error(`Unknown operation type: ${op.type}`);
        }
        
        results.push({ success: true, result });
      } catch (error) {
        results.push({ success: false, error: error.message });
      }
    }
    
    return results;
  }
  
  /**
   * Get user's organisms
   */
  async getUserOrganisms(address) {
    if (!this.contracts.registry) {
      throw new Error('Blockchain connection required');
    }
    
    const userAddress = address || (this.config.signer && await this.config.signer.getAddress());
    if (!userAddress) {
      throw new Error('Address required');
    }
    
    const organismIds = await this.contracts.registry.getUserOrganisms(userAddress);
    
    const organisms = await Promise.all(
      organismIds.map(id => this.getOrganism(id))
    );
    
    return organisms;
  }
  
  /**
   * Calculate optimal resource distribution
   */
  async optimizeResources(organismIds) {
    if (!this.contracts.swarmCoordinator) {
      throw new Error('Blockchain connection required');
    }
    
    const result = await this.contracts.swarmCoordinator.calculateOptimalDistribution(
      organismIds[0] // Assuming same swarm
    );
    
    return {
      robotIds: result.robotIds,
      taskIds: result.taskIds,
      assignments: result.assignments
    };
  }
  
  // Helper methods
  
  _initializeContracts() {
    const provider = this.config.signer || this.config.provider;
    
    this.contracts = {
      growthTracker: new ethers.Contract(
        this.config.contractAddresses.growthTracker,
        GROWTH_TRACKER_ABI,
        provider
      ),
      bioNFT: new ethers.Contract(
        this.config.contractAddresses.bioNFT,
        BIO_NFT_ABI,
        provider
      ),
      registry: new ethers.Contract(
        this.config.contractAddresses.registry,
        REGISTRY_ABI,
        provider
      )
    };
  }
  
  _createSimulatorClient() {
    return axios.create({
      baseURL: `${this.config.simulatorUrl}/api/v1`,
      headers: {
        'X-API-Key': this.config.apiKey,
        'Content-Type': 'application/json'
      },
      timeout: 30000
    });
  }
  
  _dataTypeToField(dataType) {
    const mapping = {
      [DataType.TEMPERATURE]: 'temperature',
      [DataType.HUMIDITY]: 'humidity',
      [DataType.PH_LEVEL]: 'ph',
      [DataType.LIGHT_INTENSITY]: 'lightIntensity',
      [DataType.CO2_LEVEL]: 'co2'
    };
    
    return mapping[dataType] || 'unknown';
  }
  
  _getDefaultAddresses(network) {
    const addresses = {
      mainnet: {
        registry: '0x1234567890123456789012345678901234567890',
        growthTracker: '0x2345678901234567890123456789012345678901',
        bioNFT: '0x3456789012345678901234567890123456789012',
        resourcePool: '0x4567890123456789012345678901234567890123',
        swarmCoordinator: '0x5678901234567890123456789012345678901234',
        bioOracle: '0x6789012345678901234567890123456789012345',
        decayHandler: '0x7890123456789012345678901234567890123456'
      },
      goerli: {
        registry: '0x8901234567890123456789012345678901234567',
        growthTracker: '0x9012345678901234567890123456789012345678',
        bioNFT: '0x0123456789012345678901234567890123456789',
        resourcePool: '0x1234567890123456789012345678901234567890',
        swarmCoordinator: '0x2345678901234567890123456789012345678901',
        bioOracle: '0x3456789012345678901234567890123456789012',
        decayHandler: '0x4567890123456789012345678901234567890123'
      }
    };
    
    return addresses[network] || addresses.mainnet;
  }
  
  /**
   * Disconnect and cleanup
   */
  async disconnect() {
    // Close all WebSocket connections
    this.wsConnections.forEach(ws => ws.close());
    this.wsConnections.clear();
    
    // Clear contracts
    this.contracts = {};
    
    this.emit('disconnected');
  }
}

// Utility functions

/**
 * Calculate growth rate based on environmental factors
 */
function calculateGrowthRate(biomass, environmentalFactors, geneticTraits) {
  const K = 10000; // Carrying capacity
  const r = 0.1 * (geneticTraits?.growthSpeed || 1);
  
  const tempOptimal = 22.5;
  const tempScore = 1 - Math.abs(environmentalFactors.temperature - tempOptimal) / 10;
  
  const environmentalMultiplier = Math.max(0.1, Math.min(1, tempScore));
  
  return r * biomass * (1 - biomass / K) * environmentalMultiplier;
}

/**
 * Estimate time to harvest
 */
function estimateHarvestTime(currentBiomass, growthRate, targetBiomass = 7000) {
  if (currentBiomass >= targetBiomass) return 0;
  if (growthRate <= 0) return Infinity;
  
  return Math.ceil((targetBiomass - currentBiomass) / growthRate);
}

/**
 * Convert growth stage name to enum value
 */
function stageNameToEnum(stageName) {
  return GrowthStage[stageName.toUpperCase()] || 0;
}

/**
 * Create a mock organism for testing
 */
function createMockOrganism(overrides = {}) {
  return {
    id: Math.random().toString(36).substr(2, 9),
    species: 'Tomato',
    stage: 'VEGETATIVE',
    biomass: 1500,
    health: 95,
    environmentalFactors: {
      temperature: 22,
      humidity: 65,
      ph: 6.8,
      lightIntensity: 5000,
      co2: 400
    },
    geneticTraits: {
      growthSpeed: 1.0,
      diseaseResistance: 0.8,
      yieldPotential: 1.1,
      adaptability: 0.9
    },
    ...overrides
  };
}

// Export everything
export {
  SporeSDK,
  GrowthStage,
  DataType,
  calculateGrowthRate,
  estimateHarvestTime,
  stageNameToEnum,
  createMockOrganism
};

export default SporeSDK;