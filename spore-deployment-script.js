// Spore Protocol Deployment Script
// Deploys all contracts and sets up the protocol

const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Configuration
const config = {
  network: process.env.NETWORK || "hardhat",
  verifyContracts: process.env.VERIFY === "true",
  
  // Protocol parameters
  protocolFee: 250, // 2.5%
  minValidatorStake: ethers.parseEther("0.1"),
  dataSubmissionFee: ethers.parseEther("0.0001"),
  
  // Addresses (update for mainnet)
  teamMultisig: process.env.TEAM_MULTISIG || "0x0000000000000000000000000000000000000000",
  feeRecipient: process.env.FEE_RECIPIENT || "0x0000000000000000000000000000000000000000",
  
  // Token allocations (if deploying token)
  tokenAllocations: {
    publicLiquidity: 800000, // 80%
    development: 100000,     // 10%
    team: 50000,            // 5%
    marketing: 50000        // 5%
  }
};

// Contract factories
let GrowthTracker, BioNFT, ResourcePool, SwarmCoordinator, BioOracle, DecayHandler, DataMarketplace, SporeProtocolRegistry;

async function main() {
  console.log("🌱 Spore Protocol Deployment Script");
  console.log("==================================");
  console.log(`Network: ${config.network}`);
  console.log(`Deployer: ${(await ethers.getSigners())[0].address}\n`);

  // Load contract factories
  await loadContractFactories();
  
  // Deploy contracts
  const contracts = await deployContracts();
  
  // Configure contracts
  await configureContracts(contracts);
  
  // Verify contracts if needed
  if (config.verifyContracts) {
    await verifyContracts(contracts);
  }
  
  // Save deployment data
  await saveDeploymentData(contracts);
  
  console.log("\n✅ Deployment complete!");
  console.log("======================");
  printDeploymentSummary(contracts);
}

async function loadContractFactories() {
  console.log("Loading contract factories...");
  
  GrowthTracker = await ethers.getContractFactory("GrowthTracker");
  BioNFT = await ethers.getContractFactory("BioNFT");
  ResourcePool = await ethers.getContractFactory("ResourcePool");
  SwarmCoordinator = await ethers.getContractFactory("SwarmCoordinator");
  BioOracle = await ethers.getContractFactory("BioOracle");
  DecayHandler = await ethers.getContractFactory("DecayHandler");
  DataMarketplace = await ethers.getContractFactory("DataMarketplace");
  SporeProtocolRegistry = await ethers.getContractFactory("SporeProtocolRegistry");
}

async function deployContracts() {
  const contracts = {};
  const [deployer] = await ethers.getSigners();
  
  // 1. Deploy GrowthTracker
  console.log("\n1. Deploying GrowthTracker...");
  contracts.growthTracker = await GrowthTracker.deploy();
  await contracts.growthTracker.waitForDeployment();
  console.log(`   ✓ GrowthTracker deployed to: ${await contracts.growthTracker.getAddress()}`);
  
  // 2. Deploy BioOracle
  console.log("\n2. Deploying BioOracle...");
  contracts.bioOracle = await BioOracle.deploy(await contracts.growthTracker.getAddress());
  await contracts.bioOracle.waitForDeployment();
  console.log(`   ✓ BioOracle deployed to: ${await contracts.bioOracle.getAddress()}`);
  
  // 3. Deploy BioNFT
  console.log("\n3. Deploying BioNFT...");
  contracts.bioNFT = await BioNFT.deploy(
    await contracts.growthTracker.getAddress(),
    deployer.address, // Metadata oracle (update in production)
    "https://api.sporeprotocol.io/metadata/"
  );
  await contracts.bioNFT.waitForDeployment();
  console.log(`   ✓ BioNFT deployed to: ${await contracts.bioNFT.getAddress()}`);
  
  // 4. Deploy ResourcePool
  console.log("\n4. Deploying ResourcePool...");
  contracts.resourcePool = await ResourcePool.deploy(await contracts.growthTracker.getAddress());
  await contracts.resourcePool.waitForDeployment();
  console.log(`   ✓ ResourcePool deployed to: ${await contracts.resourcePool.getAddress()}`);
  
  // 5. Deploy SwarmCoordinator
  console.log("\n5. Deploying SwarmCoordinator...");
  contracts.swarmCoordinator = await SwarmCoordinator.deploy();
  await contracts.swarmCoordinator.waitForDeployment();
  console.log(`   ✓ SwarmCoordinator deployed to: ${await contracts.swarmCoordinator.getAddress()}`);
  
  // 6. Deploy DecayHandler
  console.log("\n6. Deploying DecayHandler...");
  contracts.decayHandler = await DecayHandler.deploy(
    await contracts.growthTracker.getAddress(),
    await contracts.resourcePool.getAddress()
  );
  await contracts.decayHandler.waitForDeployment();
  console.log(`   ✓ DecayHandler deployed to: ${await contracts.decayHandler.getAddress()}`);
  
  // 7. Deploy DataMarketplace
  console.log("\n7. Deploying DataMarketplace...");
  contracts.dataMarketplace = await DataMarketplace.deploy(
    config.feeRecipient || deployer.address,
    deployer.address, // Verifier pool (update in production)
    await contracts.bioOracle.getAddress()
  );
  await contracts.dataMarketplace.waitForDeployment();
  console.log(`   ✓ DataMarketplace deployed to: ${await contracts.dataMarketplace.getAddress()}`);
  
  // 8. Deploy SporeProtocolRegistry (Upgradeable)
  console.log("\n8. Deploying SporeProtocolRegistry (Upgradeable)...");
  const Registry = await ethers.getContractFactory("SporeProtocolRegistry");
  contracts.registry = await upgrades.deployProxy(
    Registry,
    [
      deployer.address,
      config.feeRecipient || deployer.address,
      config.protocolFee
    ],
    { initializer: 'initialize' }
  );
  await contracts.registry.waitForDeployment();
  console.log(`   ✓ SporeProtocolRegistry deployed to: ${await contracts.registry.getAddress()}`);
  
  return contracts;
}

async function configureContracts(contracts) {
  console.log("\n🔧 Configuring contracts...");
  const [deployer] = await ethers.getSigners();
  
  // 1. Configure Registry with all contract addresses
  console.log("\n1. Updating registry with core contracts...");
  const tx1 = await contracts.registry.updateCoreContracts(
    await contracts.growthTracker.getAddress(),
    await contracts.bioNFT.getAddress(),
    await contracts.resourcePool.getAddress(),
    await contracts.swarmCoordinator.getAddress(),
    await contracts.bioOracle.getAddress(),
    await contracts.decayHandler.getAddress()
  );
  await tx1.wait();
  console.log("   ✓ Registry updated");
  
  // 2. Grant roles for GrowthTracker
  console.log("\n2. Configuring GrowthTracker roles...");
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"));
  
  await contracts.growthTracker.grantRole(ORACLE_ROLE, await contracts.bioOracle.getAddress());
  await contracts.growthTracker.grantRole(OPERATOR_ROLE, await contracts.registry.getAddress());
  await contracts.growthTracker.grantRole(OPERATOR_ROLE, deployer.address);
  console.log("   ✓ GrowthTracker roles configured");
  
  // 3. Configure BioNFT
  console.log("\n3. Configuring BioNFT...");
  const MINTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
  await contracts.bioNFT.grantRole(MINTER_ROLE, await contracts.registry.getAddress());
  console.log("   ✓ BioNFT roles configured");
  
  // 4. Configure ResourcePool
  console.log("\n4. Configuring ResourcePool...");
  await contracts.resourcePool.grantRole(OPERATOR_ROLE, await contracts.registry.getAddress());
  await contracts.resourcePool.grantRole(OPERATOR_ROLE, await contracts.swarmCoordinator.getAddress());
  console.log("   ✓ ResourcePool roles configured");
  
  // 5. Configure BioOracle
  console.log("\n5. Configuring BioOracle...");
  const DATA_PROVIDER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("DATA_PROVIDER_ROLE"));
  await contracts.bioOracle.grantRole(DATA_PROVIDER_ROLE, await contracts.registry.getAddress());
  await contracts.bioOracle.grantRole(DATA_PROVIDER_ROLE, deployer.address);
  console.log("   ✓ BioOracle roles configured");
  
  // 6. Configure DecayHandler
  console.log("\n6. Configuring DecayHandler...");
  await contracts.decayHandler.grantRole(OPERATOR_ROLE, await contracts.registry.getAddress());
  console.log("   ✓ DecayHandler roles configured");
  
  // 7. Register integrations in Registry
  console.log("\n7. Registering integrations...");
  await contracts.registry.registerIntegration(
    "DataMarketplace",
    "https://api.sporeprotocol.io/marketplace",
    await contracts.dataMarketplace.getAddress(),
    ethers.keccak256(ethers.toUtf8Bytes("marketplace-api-key"))
  );
  console.log("   ✓ Integrations registered");
  
  // 8. Initialize default data feeds in BioOracle
  console.log("\n8. Initializing data feeds...");
  // Data feeds are auto-initialized in constructor
  console.log("   ✓ Data feeds initialized");
  
  // 9. Transfer ownership to multisig (if provided)
  if (config.teamMultisig !== ethers.ZeroAddress) {
    console.log("\n9. Transferring ownership to multisig...");
    const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;
    
    for (const [name, contract] of Object.entries(contracts)) {
      if (contract.grantRole) {
        await contract.grantRole(DEFAULT_ADMIN_ROLE, config.teamMultisig);
        await contract.renounceRole(DEFAULT_ADMIN_ROLE, deployer.address);
        console.log(`   ✓ ${name} ownership transferred`);
      }
    }
  }
}

async function verifyContracts(contracts) {
  console.log("\n🔍 Verifying contracts on Etherscan...");
  
  const verificationTasks = [
    {
      name: "GrowthTracker",
      address: await contracts.growthTracker.getAddress(),
      constructorArguments: []
    },
    {
      name: "BioOracle",
      address: await contracts.bioOracle.getAddress(),
      constructorArguments: [await contracts.growthTracker.getAddress()]
    },
    {
      name: "BioNFT",
      address: await contracts.bioNFT.getAddress(),
      constructorArguments: [
        await contracts.growthTracker.getAddress(),
        (await ethers.getSigners())[0].address,
        "https://api.sporeprotocol.io/metadata/"
      ]
    },
    {
      name: "ResourcePool",
      address: await contracts.resourcePool.getAddress(),
      constructorArguments: [await contracts.growthTracker.getAddress()]
    },
    {
      name: "SwarmCoordinator",
      address: await contracts.swarmCoordinator.getAddress(),
      constructorArguments: []
    },
    {
      name: "DecayHandler",
      address: await contracts.decayHandler.getAddress(),
      constructorArguments: [
        await contracts.growthTracker.getAddress(),
        await contracts.resourcePool.getAddress()
      ]
    },
    {
      name: "DataMarketplace",
      address: await contracts.dataMarketplace.getAddress(),
      constructorArguments: [
        config.feeRecipient || (await ethers.getSigners())[0].address,
        (await ethers.getSigners())[0].address,
        await contracts.bioOracle.getAddress()
      ]
    }
  ];
  
  for (const task of verificationTasks) {
    try {
      await hre.run("verify:verify", {
        address: task.address,
        constructorArguments: task.constructorArguments,
      });
      console.log(`   ✓ ${task.name} verified`);
    } catch (error) {
      console.log(`   ⚠ ${task.name} verification failed: ${error.message}`);
    }
  }
}

async function saveDeploymentData(contracts) {
  console.log("\n💾 Saving deployment data...");
  
  const deploymentData = {
    network: config.network,
    timestamp: new Date().toISOString(),
    contracts: {}
  };
  
  for (const [name, contract] of Object.entries(contracts)) {
    deploymentData.contracts[name] = await contract.getAddress();
  }
  
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const filename = path.join(deploymentsDir, `${config.network}-deployment.json`);
  fs.writeFileSync(filename, JSON.stringify(deploymentData, null, 2));
  
  console.log(`   ✓ Deployment data saved to: ${filename}`);
  
  // Generate SDK config
  const sdkConfig = {
    contractAddresses: deploymentData.contracts,
    network: config.network,
    simulatorUrl: "https://api.sporeprotocol.io",
    wsUrl: "wss://stream.sporeprotocol.io"
  };
  
  const sdkConfigFile = path.join(deploymentsDir, `${config.network}-sdk-config.json`);
  fs.writeFileSync(sdkConfigFile, JSON.stringify(sdkConfig, null, 2));
  console.log(`   ✓ SDK config saved to: ${sdkConfigFile}`);
}

function printDeploymentSummary(contracts) {
  console.log("\n📋 Deployment Summary");
  console.log("====================");
  console.log("\nContract Addresses:");
  console.log("-------------------");
  
  for (const [name, contract] of Object.entries(contracts)) {
    console.log(`${name.padEnd(25)}: ${contract.target || contract.address}`);
  }
  
  console.log("\n🚀 Next Steps:");
  console.log("--------------");
  console.log("1. Update .env with deployed contract addresses");
  console.log("2. Deploy and configure the Simulator API");
  console.log("3. Initialize the first validator nodes");
  console.log("4. Create initial organism templates");
  console.log("5. Launch the web interface");
  console.log("\n📚 Documentation: https://docs.sporeprotocol.io");
  console.log("💬 Discord: https://discord.gg/sporeprotocol");
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed!");
    console.error(error);
    process.exit(1);
  });

// Helper functions for post-deployment tasks

async function createInitialOrganisms() {
  console.log("\n🌿 Creating initial organism templates...");
  
  const organisms = [
    { species: "Tomato", initialBiomass: 100, growthRate: 50 },
    { species: "Basil", initialBiomass: 50, growthRate: 60 },
    { species: "Oyster Mushroom", initialBiomass: 200, growthRate: 40 }
  ];
  
  // Implementation for creating initial organisms
}

async function setupValidators() {
  console.log("\n👥 Setting up initial validators...");
  
  // Implementation for validator setup
}

async function initializeDataFeeds() {
  console.log("\n📊 Initializing external data feeds...");
  
  // Implementation for Chainlink or other oracle integration
}

module.exports = {
  deployContracts,
  configureContracts,
  saveDeploymentData
};