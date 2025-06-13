// Spore Protocol Simulator API
// Node.js + Express backend for biological simulation

const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const compression = require('compression');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());

// Rate limiting based on API tier
const createRateLimiter = (windowMs, max) => rateLimit({
  windowMs,
  max,
  keyGenerator: (req) => req.headers['x-api-key'] || req.ip,
  handler: (req, res) => {
    res.status(429).json({
      error: 'Too many requests',
      retryAfter: Math.ceil(windowMs / 1000)
    });
  }
});

// API tiers
const apiTiers = {
  hobbyist: createRateLimiter(60 * 60 * 1000, 50000),
  professional: createRateLimiter(60 * 60 * 1000, 500000),
  enterprise: createRateLimiter(60 * 60 * 1000, Infinity)
};

// Organism models
class OrganismModel {
  constructor(species, initialBiomass = 100) {
    this.id = uuidv4();
    this.species = species;
    this.biomass = initialBiomass;
    this.stage = 'SEED';
    this.health = 100;
    this.createdAt = Date.now();
    this.lastUpdate = Date.now();
    this.environmentalFactors = {
      temperature: 22, // Celsius
      humidity: 65, // Percentage
      ph: 6.8,
      lightIntensity: 5000, // Lux
      co2: 400, // ppm
      nutrients: {
        nitrogen: 100,
        phosphorus: 50,
        potassium: 75
      }
    };
    this.geneticTraits = this.generateGeneticTraits();
  }

  generateGeneticTraits() {
    return {
      growthSpeed: Math.random() * 0.5 + 0.75, // 0.75-1.25x multiplier
      diseaseResistance: Math.random() * 0.4 + 0.6, // 0.6-1.0
      yieldPotential: Math.random() * 0.5 + 0.75, // 0.75-1.25x
      adaptability: Math.random() * 0.3 + 0.7 // 0.7-1.0
    };
  }

  // Logistic growth model
  calculateGrowth(timeDelta) {
    const K = 10000; // Carrying capacity
    const r = 0.1 * this.geneticTraits.growthSpeed; // Growth rate
    
    const environmentalMultiplier = this.calculateEnvironmentalMultiplier();
    const healthMultiplier = this.health / 100;
    
    const growth = r * this.biomass * (1 - this.biomass / K) * 
                  environmentalMultiplier * healthMultiplier * timeDelta;
    
    this.biomass = Math.max(0, Math.min(K, this.biomass + growth));
    this.updateStage();
  }

  calculateEnvironmentalMultiplier() {
    const factors = this.environmentalFactors;
    
    // Optimal ranges
    const optimalTemp = { min: 20, max: 25, optimal: 22.5 };
    const optimalHumidity = { min: 60, max: 70, optimal: 65 };
    const optimalPH = { min: 6.0, max: 7.0, optimal: 6.5 };
    
    const tempScore = this.calculateFactorScore(factors.temperature, optimalTemp);
    const humidityScore = this.calculateFactorScore(factors.humidity, optimalHumidity);
    const phScore = this.calculateFactorScore(factors.ph, optimalPH);
    
    return (tempScore + humidityScore + phScore) / 3 * this.geneticTraits.adaptability;
  }

  calculateFactorScore(value, optimal) {
    if (value >= optimal.min && value <= optimal.max) {
      const distance = Math.abs(value - optimal.optimal);
      const maxDistance = Math.max(
        optimal.optimal - optimal.min,
        optimal.max - optimal.optimal
      );
      return 1 - (distance / maxDistance) * 0.5;
    }
    return 0.5; // Suboptimal but not lethal
  }

  updateStage() {
    const stages = [
      { name: 'SEED', minBiomass: 0 },
      { name: 'GERMINATION', minBiomass: 200 },
      { name: 'VEGETATIVE', minBiomass: 1000 },
      { name: 'FLOWERING', minBiomass: 3000 },
      { name: 'FRUITING', minBiomass: 5000 },
      { name: 'HARVEST', minBiomass: 7000 }
    ];

    for (let i = stages.length - 1; i >= 0; i--) {
      if (this.biomass >= stages[i].minBiomass) {
        this.stage = stages[i].name;
        break;
      }
    }
  }

  updateEnvironment(factors) {
    Object.assign(this.environmentalFactors, factors);
    
    // Environmental stress affects health
    const stress = this.calculateEnvironmentalStress();
    this.health = Math.max(0, Math.min(100, this.health - stress));
  }

  calculateEnvironmentalStress() {
    const multiplier = this.calculateEnvironmentalMultiplier();
    return (1 - multiplier) * 2; // 0-2 health loss per update
  }

  simulate(timeDelta = 1) {
    this.calculateGrowth(timeDelta);
    this.lastUpdate = Date.now();
    
    // Random events
    if (Math.random() < 0.01) {
      this.triggerRandomEvent();
    }
    
    return this.getState();
  }

  triggerRandomEvent() {
    const events = [
      { type: 'pest_attack', healthImpact: -10 },
      { type: 'nutrient_boost', growthBoost: 1.2 },
      { type: 'drought_stress', healthImpact: -5 },
      { type: 'beneficial_microbes', healthImpact: 5 }
    ];
    
    const event = events[Math.floor(Math.random() * events.length)];
    
    if (event.healthImpact) {
      this.health = Math.max(0, Math.min(100, this.health + event.healthImpact));
    }
    
    return event;
  }

  getState() {
    return {
      id: this.id,
      species: this.species,
      stage: this.stage,
      biomass: Math.round(this.biomass * 100) / 100,
      health: Math.round(this.health * 100) / 100,
      environmentalFactors: this.environmentalFactors,
      geneticTraits: this.geneticTraits,
      age: Date.now() - this.createdAt,
      lastUpdate: this.lastUpdate
    };
  }

  predict(hours = 24) {
    const predictions = [];
    const tempOrganism = Object.assign(Object.create(Object.getPrototypeOf(this)), this);
    
    for (let h = 1; h <= hours; h++) {
      tempOrganism.simulate(1);
      predictions.push({
        hour: h,
        biomass: tempOrganism.biomass,
        stage: tempOrganism.stage,
        health: tempOrganism.health
      });
    }
    
    return {
      current: this.getState(),
      predictions,
      estimatedHarvestTime: this.estimateHarvestTime()
    };
  }

  estimateHarvestTime() {
    const harvestBiomass = 7000;
    if (this.biomass >= harvestBiomass) return 0;
    
    const currentGrowthRate = this.calculateGrowthRate();
    if (currentGrowthRate <= 0) return -1; // Not growing
    
    return Math.ceil((harvestBiomass - this.biomass) / currentGrowthRate);
  }

  calculateGrowthRate() {
    const K = 10000;
    const r = 0.1 * this.geneticTraits.growthSpeed;
    const environmentalMultiplier = this.calculateEnvironmentalMultiplier();
    const healthMultiplier = this.health / 100;
    
    return r * this.biomass * (1 - this.biomass / K) * 
           environmentalMultiplier * healthMultiplier;
  }
}

// Organism storage (in production, use database)
const organisms = new Map();

// WebSocket connections for real-time streaming
const wsConnections = new Map();

// Middleware to validate API key
const validateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  if (!apiKey) {
    return res.status(401).json({ error: 'API key required' });
  }
  
  // In production, validate against database
  const tier = apiKey.startsWith('sk_live_ent_') ? 'enterprise' :
               apiKey.startsWith('sk_live_pro_') ? 'professional' : 'hobbyist';
  
  req.apiTier = tier;
  apiTiers[tier](req, res, next);
};

// Routes

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Create organism
app.post('/api/v1/organisms', validateApiKey, (req, res) => {
  const { species, initialBiomass } = req.body;
  
  if (!species) {
    return res.status(400).json({ error: 'Species required' });
  }
  
  const organism = new OrganismModel(species, initialBiomass);
  organisms.set(organism.id, organism);
  
  res.status(201).json({
    organism: organism.getState(),
    message: 'Organism created successfully'
  });
});

// Get organism
app.get('/api/v1/organisms/:id', validateApiKey, (req, res) => {
  const organism = organisms.get(req.params.id);
  
  if (!organism) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  res.json(organism.getState());
});

// Update organism
app.put('/api/v1/organisms/:id', validateApiKey, (req, res) => {
  const organism = organisms.get(req.params.id);
  
  if (!organism) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  const { simulate, environmentalFactors } = req.body;
  
  if (environmentalFactors) {
    organism.updateEnvironment(environmentalFactors);
  }
  
  if (simulate) {
    organism.simulate();
  }
  
  res.json(organism.getState());
});

// Delete organism
app.delete('/api/v1/organisms/:id', validateApiKey, (req, res) => {
  if (!organisms.has(req.params.id)) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  organisms.delete(req.params.id);
  
  // Close any WebSocket connections
  const ws = wsConnections.get(req.params.id);
  if (ws) {
    ws.close();
    wsConnections.delete(req.params.id);
  }
  
  res.json({ message: 'Organism deleted successfully' });
});

// Get historical data
app.get('/api/v1/data/:organismId/historical', validateApiKey, (req, res) => {
  const organism = organisms.get(req.params.organismId);
  
  if (!organism) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  // In production, retrieve from time-series database
  const mockHistorical = [];
  const currentState = organism.getState();
  
  for (let i = 23; i >= 0; i--) {
    mockHistorical.push({
      timestamp: Date.now() - (i * 3600000),
      biomass: currentState.biomass * (1 - i * 0.03),
      health: Math.max(80, currentState.health - i * 0.5),
      stage: i > 12 ? 'VEGETATIVE' : currentState.stage
    });
  }
  
  res.json({
    organismId: req.params.organismId,
    dataPoints: mockHistorical,
    resolution: 'hourly'
  });
});

// Predict growth
app.post('/api/v1/data/:organismId/predict', validateApiKey, (req, res) => {
  const organism = organisms.get(req.params.organismId);
  
  if (!organism) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  const { hours = 24 } = req.body;
  const predictions = organism.predict(hours);
  
  res.json(predictions);
});

// Environment endpoints
app.post('/api/v1/environments', validateApiKey, (req, res) => {
  const { name, conditions } = req.body;
  
  // In production, store in database
  const environment = {
    id: uuidv4(),
    name,
    conditions: {
      temperature: 22,
      humidity: 65,
      ph: 6.8,
      lightIntensity: 5000,
      co2: 400,
      ...conditions
    },
    createdAt: new Date().toISOString()
  };
  
  res.status(201).json(environment);
});

// Update environment conditions
app.put('/api/v1/environments/:id/conditions', validateApiKey, (req, res) => {
  const { conditions } = req.body;
  
  // Update all organisms in this environment
  const affectedOrganisms = [];
  
  organisms.forEach(organism => {
    organism.updateEnvironment(conditions);
    affectedOrganisms.push(organism.id);
  });
  
  res.json({
    message: 'Environment updated',
    affectedOrganisms: affectedOrganisms.length
  });
});

// Chaos testing endpoint
app.post('/api/v1/chaos/trigger', validateApiKey, (req, res) => {
  const { organismId, event } = req.body;
  
  const organism = organisms.get(organismId);
  if (!organism) {
    return res.status(404).json({ error: 'Organism not found' });
  }
  
  const chaosEvents = {
    pest_outbreak: () => {
      organism.health = Math.max(0, organism.health - 25);
    },
    nutrient_deficiency: () => {
      organism.environmentalFactors.nutrients.nitrogen *= 0.5;
    },
    heat_wave: () => {
      organism.environmentalFactors.temperature = 35;
    },
    power_outage: () => {
      organism.environmentalFactors.lightIntensity = 0;
    }
  };
  
  if (chaosEvents[event]) {
    chaosEvents[event]();
    res.json({
      message: `Chaos event '${event}' triggered`,
      organism: organism.getState()
    });
  } else {
    res.status(400).json({ error: 'Invalid chaos event' });
  }
});

// WebSocket server for real-time streaming
const wss = new WebSocket.Server({ port: 3001 });

wss.on('connection', (ws, req) => {
  const organismId = new URL(req.url, `http://${req.headers.host}`).searchParams.get('organismId');
  
  if (!organismId || !organisms.has(organismId)) {
    ws.close(1008, 'Invalid organism ID');
    return;
  }
  
  wsConnections.set(organismId, ws);
  
  // Send initial state
  ws.send(JSON.stringify({
    type: 'initial',
    data: organisms.get(organismId).getState()
  }));
  
  // Set up real-time updates
  const interval = setInterval(() => {
    const organism = organisms.get(organismId);
    if (organism && ws.readyState === WebSocket.OPEN) {
      organism.simulate(0.1); // Simulate 0.1 time units
      ws.send(JSON.stringify({
        type: 'update',
        data: organism.getState()
      }));
    } else {
      clearInterval(interval);
    }
  }, 1000); // Update every second
  
  ws.on('close', () => {
    clearInterval(interval);
    wsConnections.delete(organismId);
  });
  
  ws.on('message', (message) => {
    try {
      const { action, data } = JSON.parse(message);
      const organism = organisms.get(organismId);
      
      if (action === 'updateEnvironment' && organism) {
        organism.updateEnvironment(data);
        ws.send(JSON.stringify({
          type: 'environmentUpdated',
          data: organism.getState()
        }));
      }
    } catch (error) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid message format'
      }));
    }
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Start server
app.listen(PORT, () => {
  console.log(`Spore Protocol Simulator API running on port ${PORT}`);
  console.log(`WebSocket server running on port 3001`);
});

// Cleanup function
process.on('SIGTERM', () => {
  console.log('SIGTERM received, closing connections...');
  
  // Close all WebSocket connections
  wsConnections.forEach(ws => ws.close());
  
  // Close HTTP server
  app.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

module.exports = app;