#!/usr/bin/env node

// Spore Protocol CLI Tool
// Command-line interface for interacting with Spore Protocol

const { Command } = require('commander');
const { ethers } = require('ethers');
const chalk = require('chalk');
const ora = require('ora');
const prompts = require('prompts');
const Table = require('cli-table3');
const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');
const WebSocket = require('ws');

// Load environment and config
require('dotenv').config();

const program = new Command();
const CONFIG_FILE = path.join(process.env.HOME || process.env.USERPROFILE, '.spore', 'config.json');

// Utility functions
const loadConfig = async () => {
  try {
    const data = await fs.readFile(CONFIG_FILE, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    return {
      rpcUrl: process.env.RPC_URL || 'http://localhost:8545',
      apiUrl: process.env.API_URL || 'http://localhost:3000',
      wsUrl: process.env.WS_URL || 'ws://localhost:3001',
      privateKey: process.env.PRIVATE_KEY,
      apiKey: process.env.API_KEY,
      contracts: {}
    };
  }
};

const saveConfig = async (config) => {
  const dir = path.dirname(CONFIG_FILE);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(CONFIG_FILE, JSON.stringify(config, null, 2));
};

const getProvider = async () => {
  const config = await loadConfig();
  return new ethers.JsonRpcProvider(config.rpcUrl);
};

const getSigner = async () => {
  const config = await loadConfig();
  if (!config.privateKey) {
    throw new Error('Private key not configured. Run "spore config" first.');
  }
  const provider = await getProvider();
  return new ethers.Wallet(config.privateKey, provider);
};

const getContracts = async () => {
  const config = await loadConfig();
  const signer = await getSigner();
  
  // Load ABIs (simplified for example)
  const registryABI = [
    "function registerOrganism(string species, uint64 initialBiomass, uint16 growthRate, bytes metadata) payable returns (uint256)",
    "function getOrganismData(uint256 organismId) view returns (tuple(uint256 growthTrackerId, uint256 bioNFTId, address owner, uint256 registrationBlock, bool isActive, string species, bytes metadata) registration, uint256 currentStage, uint256 health, uint256 biomass, tuple(uint16 growthSpeed, uint16 diseaseResistance, uint16 yieldPotential, uint16 adaptability, uint8 generation, uint8 rarity) genetics)",
    "function getUserOrganisms(address user) view returns (uint256[])"
  ];
  
  return {
    registry: new ethers.Contract(config.contracts.registry || ethers.ZeroAddress, registryABI, signer)
  };
};

const getAPI = async () => {
  const config = await loadConfig();
  return axios.create({
    baseURL: `${config.apiUrl}/api/v1`,
    headers: config.apiKey ? { 'X-API-Key': config.apiKey } : {}
  });
};

// Format utilities
const formatEther = (value) => {
  return ethers.formatEther(value) + ' ETH';
};

const formatAddress = (address) => {
  return address.slice(0, 6) + '...' + address.slice(-4);
};

const formatStage = (stage) => {
  const stages = ['SEED', 'GERMINATION', 'VEGETATIVE', 'FLOWERING', 'FRUITING', 'HARVEST', 'DECAY'];
  return stages[stage] || 'UNKNOWN';
};

// Commands

program
  .name('spore')
  .description('CLI tool for Spore Protocol')
  .version('1.0.0');

// Config command
program
  .command('config')
  .description('Configure Spore CLI')
  .action(async () => {
    const config = await loadConfig();
    
    const response = await prompts([
      {
        type: 'text',
        name: 'rpcUrl',
        message: 'Ethereum RPC URL:',
        initial: config.rpcUrl
      },
      {
        type: 'text',
        name: 'apiUrl',
        message: 'Simulator API URL:',
        initial: config.apiUrl
      },
      {
        type: 'text',
        name: 'wsUrl',
        message: 'WebSocket URL:',
        initial: config.wsUrl
      },
      {
        type: 'password',
        name: 'privateKey',
        message: 'Private key (leave empty to skip):',
        initial: config.privateKey
      },
      {
        type: 'text',
        name: 'apiKey',
        message: 'API key (leave empty to skip):',
        initial: config.apiKey
      }
    ]);
    
    // Merge with existing config
    const newConfig = { ...config, ...response };
    
    // Test connection
    const spinner = ora('Testing connection...').start();
    try {
      const provider = new ethers.JsonRpcProvider(newConfig.rpcUrl);
      await provider.getNetwork();
      spinner.succeed('Connected to blockchain');
      
      const api = axios.create({ baseURL: `${newConfig.apiUrl}/health` });
      await api.get('/');
      spinner.succeed('Connected to API');
      
      await saveConfig(newConfig);
      console.log(chalk.green('✓ Configuration saved'));
    } catch (error) {
      spinner.fail('Connection failed: ' + error.message);
    }
  });

// Create organism command
program
  .command('create')
  .description('Create a new organism')
  .option('-s, --species <species>', 'Organism species', 'Tomato')
  .option('-b, --biomass <biomass>', 'Initial biomass', '100')
  .option('-g, --growth-rate <rate>', 'Growth rate (1-100)', '50')
  .option('--no-simulator', 'Skip simulator creation')
  .action(async (options) => {
    const spinner = ora('Creating organism...').start();
    
    try {
      const signer = await getSigner();
      const contracts = await getContracts();
      const api = await getAPI();
      
      // Create on blockchain
      const tx = await contracts.registry.registerOrganism(
        options.species,
        options.biomass,
        options.growthRate,
        '0x',
        { value: ethers.parseEther('0.01') }
      );
      
      spinner.text = 'Waiting for transaction confirmation...';
      const receipt = await tx.wait();
      
      // Get organism ID from events
      const event = receipt.logs.find(log => 
        log.topics[0] === ethers.id('OrganismRegistered(uint256,address,string)')
      );
      const organismId = event ? parseInt(event.topics[1], 16) : 0;
      
      spinner.succeed(`Organism created on blockchain (ID: ${organismId})`);
      console.log(chalk.gray(`Transaction: ${receipt.hash}`));
      
      // Create in simulator
      if (options.simulator !== false) {
        spinner.start('Creating in simulator...');
        const simResponse = await api.post('/organisms', {
          species: options.species,
          initialBiomass: parseInt(options.biomass)
        });
        spinner.succeed(`Simulator organism created (ID: ${simResponse.data.organism.id})`);
      }
      
      console.log(chalk.green('\n✓ Organism successfully created!'));
      
      // Display summary
      const table = new Table({
        head: ['Property', 'Value'],
        style: { head: ['cyan'] }
      });
      
      table.push(
        ['Species', options.species],
        ['Initial Biomass', options.biomass + ' mg'],
        ['Growth Rate', options.growthRate],
        ['Blockchain ID', organismId],
        ['Cost', '0.01 ETH']
      );
      
      console.log('\n' + table.toString());
      
    } catch (error) {
      spinner.fail('Failed to create organism: ' + error.message);
    }
  });

// List organisms command
program
  .command('list')
  .description('List your organisms')
  .option('-a, --address <address>', 'Address to query (default: your address)')
  .action(async (options) => {
    const spinner = ora('Fetching organisms...').start();
    
    try {
      const signer = await getSigner();
      const contracts = await getContracts();
      
      const address = options.address || await signer.getAddress();
      const organismIds = await contracts.registry.getUserOrganisms(address);
      
      if (organismIds.length === 0) {
        spinner.info('No organisms found');
        return;
      }
      
      spinner.text = 'Loading organism data...';
      
      const table = new Table({
        head: ['ID', 'Species', 'Stage', 'Biomass', 'Health', 'Status'],
        style: { head: ['cyan'] }
      });
      
      for (const id of organismIds) {
        const data = await contracts.registry.getOrganismData(id);
        
        table.push([
          id.toString(),
          data.registration.species,
          formatStage(data.currentStage),
          data.biomass.toString() + ' mg',
          (Number(data.health) / 100).toFixed(1) + '%',
          data.registration.isActive ? chalk.green('Active') : chalk.red('Inactive')
        ]);
      }
      
      spinner.succeed(`Found ${organismIds.length} organism(s)`);
      console.log('\n' + table.toString());
      
    } catch (error) {
      spinner.fail('Failed to fetch organisms: ' + error.message);
    }
  });

// Get organism details
program
  .command('get <id>')
  .description('Get detailed organism information')
  .option('--history', 'Include historical data')
  .action(async (id, options) => {
    const spinner = ora('Fetching organism data...').start();
    
    try {
      const contracts = await getContracts();
      const api = await getAPI();
      
      // Get blockchain data
      const data = await contracts.registry.getOrganismData(id);
      spinner.succeed('Organism data retrieved');
      
      // Display basic info
      console.log(chalk.bold('\n📊 Organism Details\n'));
      
      const basicTable = new Table({
        head: ['Property', 'Value'],
        style: { head: ['cyan'] }
      });
      
      basicTable.push(
        ['ID', id],
        ['Species', data.registration.species],
        ['Owner', formatAddress(data.registration.owner)],
        ['Stage', formatStage(data.currentStage)],
        ['Biomass', data.biomass.toString() + ' mg'],
        ['Health', (Number(data.health) / 100).toFixed(1) + '%'],
        ['Status', data.registration.isActive ? chalk.green('Active') : chalk.red('Inactive')]
      );
      
      console.log(basicTable.toString());
      
      // Display genetics
      console.log(chalk.bold('\n🧬 Genetic Profile\n'));
      
      const geneticsTable = new Table({
        head: ['Trait', 'Value', 'Rating'],
        style: { head: ['cyan'] }
      });
      
      const genetics = data.genetics;
      geneticsTable.push(
        ['Growth Speed', (Number(genetics.growthSpeed) / 100).toFixed(1) + '%', getRating(genetics.growthSpeed)],
        ['Disease Resistance', (Number(genetics.diseaseResistance) / 100).toFixed(1) + '%', getRating(genetics.diseaseResistance)],
        ['Yield Potential', (Number(genetics.yieldPotential) / 100).toFixed(1) + '%', getRating(genetics.yieldPotential)],
        ['Adaptability', (Number(genetics.adaptability) / 100).toFixed(1) + '%', getRating(genetics.adaptability)],
        ['Generation', genetics.generation.toString(), '-'],
        ['Rarity', getRarityName(genetics.rarity), getRarityColor(genetics.rarity)]
      );
      
      console.log(geneticsTable.toString());
      
      // Get historical data if requested
      if (options.history) {
        spinner.start('Fetching historical data...');
        try {
          const history = await api.get(`/data/${id}/historical`);
          spinner.succeed('Historical data retrieved');
          
          console.log(chalk.bold('\n📈 Recent History\n'));
          
          const historyTable = new Table({
            head: ['Time', 'Biomass', 'Health', 'Stage'],
            style: { head: ['cyan'] }
          });
          
          history.data.dataPoints.slice(-10).forEach(point => {
            historyTable.push([
              new Date(point.timestamp).toLocaleString(),
              point.biomass.toFixed(1) + ' mg',
              point.health.toFixed(1) + '%',
              point.stage
            ]);
          });
          
          console.log(historyTable.toString());
        } catch (error) {
          spinner.fail('Could not fetch historical data');
        }
      }
      
    } catch (error) {
      spinner.fail('Failed to get organism: ' + error.message);
    }
  });

// Monitor organism in real-time
program
  .command('monitor <id>')
  .description('Monitor organism in real-time')
  .option('-d, --duration <seconds>', 'Monitoring duration', '60')
  .action(async (id, options) => {
    const config = await loadConfig();
    const spinner = ora('Connecting to real-time stream...').start();
    
    try {
      const ws = new WebSocket(`${config.wsUrl}?organismId=${id}`);
      let updateCount = 0;
      const startTime = Date.now();
      const duration = parseInt(options.duration) * 1000;
      
      ws.on('open', () => {
        spinner.succeed('Connected to real-time stream');
        console.log(chalk.gray(`Monitoring for ${options.duration} seconds...\n`));
      });
      
      ws.on('message', (data) => {
        const message = JSON.parse(data);
        
        if (message.type === 'update') {
          updateCount++;
          const update = message.data;
          
          // Clear previous line and display update
          process.stdout.write('\r' + ' '.repeat(80) + '\r');
          process.stdout.write(
            `[${new Date().toLocaleTimeString()}] ` +
            `Biomass: ${chalk.green(update.biomass.toFixed(1) + ' mg')} | ` +
            `Health: ${chalk.yellow(update.health.toFixed(1) + '%')} | ` +
            `Stage: ${chalk.cyan(update.stage)} | ` +
            `Updates: ${updateCount}`
          );
        }
        
        // Check if duration exceeded
        if (Date.now() - startTime > duration) {
          ws.close();
        }
      });
      
      ws.on('close', () => {
        console.log(chalk.green('\n\n✓ Monitoring complete'));
        console.log(chalk.gray(`Total updates received: ${updateCount}`));
        process.exit(0);
      });
      
      ws.on('error', (error) => {
        spinner.fail('Stream error: ' + error.message);
        process.exit(1);
      });
      
    } catch (error) {
      spinner.fail('Failed to connect: ' + error.message);
    }
  });

// Update environmental conditions
program
  .command('update <id>')
  .description('Update organism environmental conditions')
  .option('-t, --temperature <value>', 'Temperature in Celsius')
  .option('-h, --humidity <value>', 'Humidity percentage')
  .option('-p, --ph <value>', 'pH level')
  .option('-l, --light <value>', 'Light intensity in lux')
  .option('-c, --co2 <value>', 'CO2 level in ppm')
  .action(async (id, options) => {
    const spinner = ora('Updating environmental conditions...').start();
    
    try {
      const api = await getAPI();
      
      const updates = {};
      if (options.temperature) updates.temperature = parseFloat(options.temperature);
      if (options.humidity) updates.humidity = parseFloat(options.humidity);
      if (options.ph) updates.ph = parseFloat(options.ph);
      if (options.light) updates.lightIntensity = parseInt(options.light);
      if (options.co2) updates.co2 = parseInt(options.co2);
      
      const response = await api.put(`/organisms/${id}`, {
        environmentalFactors: updates
      });
      
      spinner.succeed('Environmental conditions updated');
      
      const table = new Table({
        head: ['Factor', 'New Value'],
        style: { head: ['cyan'] }
      });
      
      Object.entries(updates).forEach(([key, value]) => {
        table.push([key, value]);
      });
      
      console.log('\n' + table.toString());
      
    } catch (error) {
      spinner.fail('Failed to update conditions: ' + error.message);
    }
  });

// Predict growth
program
  .command('predict <id>')
  .description('Predict organism growth')
  .option('-h, --hours <hours>', 'Prediction timeframe in hours', '24')
  .action(async (id, options) => {
    const spinner = ora('Generating predictions...').start();
    
    try {
      const api = await getAPI();
      
      const response = await api.post(`/data/${id}/predict`, {
        hours: parseInt(options.hours)
      });
      
      spinner.succeed('Predictions generated');
      
      const predictions = response.data.predictions;
      const current = response.data.current;
      
      console.log(chalk.bold('\n🔮 Growth Predictions\n'));
      
      // Current state
      console.log(chalk.gray('Current State:'));
      console.log(`  Biomass: ${current.biomass.toFixed(1)} mg`);
      console.log(`  Health: ${current.health.toFixed(1)}%`);
      console.log(`  Stage: ${current.stage}\n`);
      
      // Predictions table
      const table = new Table({
        head: ['Hour', 'Biomass (mg)', 'Health (%)', 'Stage'],
        style: { head: ['cyan'] }
      });
      
      // Show every 4 hours for readability
      predictions.filter((_, i) => i % 4 === 3).forEach(pred => {
        table.push([
          pred.hour,
          pred.biomass.toFixed(1),
          pred.health.toFixed(1),
          pred.stage
        ]);
      });
      
      console.log(table.toString());
      
      // Harvest prediction
      if (response.data.estimatedHarvestTime > 0) {
        console.log(chalk.green(`\n🌾 Estimated harvest time: ${response.data.estimatedHarvestTime} hours`));
      } else if (response.data.estimatedHarvestTime === 0) {
        console.log(chalk.green('\n🌾 Ready for harvest!'));
      } else {
        console.log(chalk.yellow('\n⚠️  Growth stalled - check environmental conditions'));
      }
      
    } catch (error) {
      spinner.fail('Failed to generate predictions: ' + error.message);
    }
  });

// Run experiment
program
  .command('experiment')
  .description('Run a growth experiment')
  .option('-s, --species <species>', 'Species to test', 'Tomato')
  .option('-d, --duration <hours>', 'Experiment duration', '168')
  .option('-r, --replications <count>', 'Number of replications', '3')
  .action(async (options) => {
    const spinner = ora('Setting up experiment...').start();
    
    try {
      const api = await getAPI();
      
      // Define experimental conditions
      const conditions = [
        { name: 'Control', temperature: 22, humidity: 65, ph: 6.8 },
        { name: 'High Temp', temperature: 28, humidity: 65, ph: 6.8 },
        { name: 'Low pH', temperature: 22, humidity: 65, ph: 5.5 },
        { name: 'Optimal', temperature: 24, humidity: 70, ph: 6.5 }
      ];
      
      console.log(chalk.bold('\n🧪 Experimental Design\n'));
      
      const designTable = new Table({
        head: ['Condition', 'Temperature (°C)', 'Humidity (%)', 'pH'],
        style: { head: ['cyan'] }
      });
      
      conditions.forEach(cond => {
        designTable.push([cond.name, cond.temperature, cond.humidity, cond.ph]);
      });
      
      console.log(designTable.toString());
      
      const confirm = await prompts({
        type: 'confirm',
        name: 'value',
        message: 'Start experiment?',
        initial: true
      });
      
      if (!confirm.value) return;
      
      // Run experiment
      spinner.start('Running experiment...');
      const results = [];
      
      for (let c = 0; c < conditions.length; c++) {
        for (let r = 0; r < parseInt(options.replications); r++) {
          spinner.text = `Running condition ${c + 1}/${conditions.length}, replication ${r + 1}/${options.replications}...`;
          
          // Create organism
          const createResp = await api.post('/organisms', {
            species: options.species,
            initialBiomass: 100
          });
          
          const organismId = createResp.data.organism.id;
          
          // Apply conditions
          await api.put(`/organisms/${organismId}`, {
            environmentalFactors: {
              temperature: conditions[c].temperature,
              humidity: conditions[c].humidity,
              ph: conditions[c].ph
            }
          });
          
          // Simulate growth
          for (let h = 0; h < parseInt(options.duration); h += 24) {
            await api.put(`/organisms/${organismId}`, { simulate: true });
          }
          
          // Get final state
          const finalResp = await api.get(`/organisms/${organismId}`);
          
          results.push({
            condition: conditions[c].name,
            replication: r + 1,
            finalBiomass: finalResp.data.biomass,
            finalHealth: finalResp.data.health,
            finalStage: finalResp.data.stage
          });
        }
      }
      
      spinner.succeed('Experiment complete!');
      
      // Analyze results
      console.log(chalk.bold('\n📊 Results Summary\n'));
      
      const resultsTable = new Table({
        head: ['Condition', 'Avg Biomass (mg)', 'Avg Health (%)', 'Success Rate (%)'],
        style: { head: ['cyan'] }
      });
      
      conditions.forEach(cond => {
        const condResults = results.filter(r => r.condition === cond.name);
        const avgBiomass = condResults.reduce((sum, r) => sum + r.finalBiomass, 0) / condResults.length;
        const avgHealth = condResults.reduce((sum, r) => sum + r.finalHealth, 0) / condResults.length;
        const successRate = (condResults.filter(r => r.finalStage === 'HARVEST').length / condResults.length) * 100;
        
        resultsTable.push([
          cond.name,
          avgBiomass.toFixed(1),
          avgHealth.toFixed(1),
          successRate.toFixed(0)
        ]);
      });
      
      console.log(resultsTable.toString());
      
      // Find best condition
      const bestCondition = conditions.reduce((best, cond) => {
        const condResults = results.filter(r => r.condition === cond.name);
        const avgBiomass = condResults.reduce((sum, r) => sum + r.finalBiomass, 0) / condResults.length;
        return avgBiomass > best.biomass ? { name: cond.name, biomass: avgBiomass } : best;
      }, { name: '', biomass: 0 });
      
      console.log(chalk.green(`\n✨ Best condition: ${bestCondition.name}`));
      
    } catch (error) {
      spinner.fail('Experiment failed: ' + error.message);
    }
  });

// Network info command
program
  .command('network')
  .description('Display network information')
  .action(async () => {
    const spinner = ora('Fetching network info...').start();
    
    try {
      const provider = await getProvider();
      const config = await loadConfig();
      
      const network = await provider.getNetwork();
      const blockNumber = await provider.getBlockNumber();
      const gasPrice = await provider.getFeeData();
      
      spinner.succeed('Network information retrieved');
      
      const table = new Table({
        head: ['Property', 'Value'],
        style: { head: ['cyan'] }
      });
      
      table.push(
        ['Network', network.name || 'Unknown'],
        ['Chain ID', network.chainId.toString()],
        ['RPC URL', config.rpcUrl],
        ['Current Block', blockNumber.toString()],
        ['Gas Price', ethers.formatUnits(gasPrice.gasPrice || 0, 'gwei') + ' gwei'],
        ['API URL', config.apiUrl],
        ['WebSocket URL', config.wsUrl]
      );
      
      console.log('\n' + table.toString());
      
      // Check contract deployment
      if (config.contracts.registry) {
        spinner.start('Checking contract deployment...');
        const code = await provider.getCode(config.contracts.registry);
        if (code !== '0x') {
          spinner.succeed('Registry contract deployed at: ' + config.contracts.registry);
        } else {
          spinner.fail('Registry contract not found at configured address');
        }
      }
      
    } catch (error) {
      spinner.fail('Failed to get network info: ' + error.message);
    }
  });

// Helper functions
function getRating(value) {
  const percent = Number(value) / 100;
  if (percent >= 90) return chalk.green('Excellent');
  if (percent >= 70) return chalk.yellow('Good');
  if (percent >= 50) return chalk.gray('Average');
  return chalk.red('Poor');
}

function getRarityName(rarity) {
  const names = ['Basic', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'];
  return names[rarity] || 'Unknown';
}

function getRarityColor(rarity) {
  const colors = [
    chalk.gray('⚪'),
    chalk.white('⚪'),
    chalk.green('🟢'),
    chalk.blue('🔵'),
    chalk.magenta('🟣'),
    chalk.yellow('🟡')
  ];
  return colors[rarity] || chalk.gray('⚪');
}

// Error handling
process.on('unhandledRejection', (error) => {
  console.error(chalk.red('Error: ' + error.message));
  process.exit(1);
});

// Parse commands
program.parse(process.argv);

// Show help if no command provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
}