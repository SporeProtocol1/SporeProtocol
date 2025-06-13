// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IGrowthTracker.sol";

/**
 * @title BioNFT
 * @author Spore Protocol
 * @notice Dynamic NFTs that evolve based on organism state
 * @dev Integrates with GrowthTracker for real-time metadata updates
 */
contract BioNFT is ERC721Enumerable, ERC721URIStorage, AccessControl {
    using Strings for uint256;
    using ECDSA for bytes32;
    
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Genetic traits stored on-chain
    struct GeneticProfile {
        uint16 growthSpeed;     // 0-10000 (affects growth rate)
        uint16 diseaseResistance; // 0-10000 (affects health degradation)
        uint16 yieldPotential;  // 0-10000 (affects final biomass)
        uint16 adaptability;    // 0-10000 (affects env factor tolerance)
        uint8 generation;       // Generation number
        uint8 rarity;          // 0-5 (common to legendary)
    }
    
    struct BioMetadata {
        string species;
        uint256 growthTrackerId;
        uint256 parentId1;
        uint256 parentId2;
        uint256 birthTimestamp;
        GeneticProfile genetics;
        string currentImageURI;
    }
    
    // Storage
    mapping(uint256 => BioMetadata) public bioData;
    mapping(uint256 => mapping(uint256 => string)) public stageImageURIs;
    mapping(bytes32 => bool) public usedSignatures;
    
    IGrowthTracker public growthTracker;
    address public metadataOracle;
    string public baseURI;
    uint256 public nextTokenId;
    
    // Evolution thresholds
    mapping(string => mapping(uint256 => uint256)) public evolutionThresholds;
    
    // Events
    event BioNFTMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 growthTrackerId,
        string species
    );
    event MetadataUpdated(uint256 indexed tokenId, string newImageURI);
    event GeneticsRevealed(uint256 indexed tokenId, GeneticProfile genetics);
    event EvolutionTriggered(uint256 indexed tokenId, uint256 stage);
    
    // Errors
    error InvalidGrowthTracker();
    error InvalidSignature();
    error SignatureAlreadyUsed();
    error TokenNotExists();
    error InvalidGeneticValue();
    
    constructor(
        address _growthTracker,
        address _metadataOracle,
        string memory _baseURI
    ) ERC721("Spore Protocol BioNFT", "SPORE-BIO") {
        if (_growthTracker == address(0)) revert InvalidGrowthTracker();
        
        growthTracker = IGrowthTracker(_growthTracker);
        metadataOracle = _metadataOracle;
        baseURI = _baseURI;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }
    
    /**
     * @notice Mints a new BioNFT linked to a GrowthTracker organism
     * @param to Recipient address
     * @param species Species name
     * @param growthTrackerId ID from GrowthTracker contract
     * @param parentIds Parent NFT IDs for genetic inheritance
     * @return tokenId The minted token ID
     */
    function mintBioNFT(
        address to,
        string memory species,
        uint256 growthTrackerId,
        uint256[2] memory parentIds
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        
        // Generate initial genetics
        GeneticProfile memory genetics = _generateGenetics(parentIds);
        
        bioData[tokenId] = BioMetadata({
            species: species,
            growthTrackerId: growthTrackerId,
            parentId1: parentIds[0],
            parentId2: parentIds[1],
            birthTimestamp: block.timestamp,
            genetics: genetics,
            currentImageURI: _getInitialImageURI(species)
        });
        
        _safeMint(to, tokenId);
        
        emit BioNFTMinted(tokenId, to, growthTrackerId, species);
        emit GeneticsRevealed(tokenId, genetics);
    }
    
    /**
     * @notice Updates NFT metadata based on organism growth stage
     * @param tokenId Token to update
     * @param signature Oracle signature verifying the update
     * @param newImageURI New image URI for current stage
     */
    function updateMetadata(
        uint256 tokenId,
        bytes memory signature,
        string memory newImageURI
    ) external {
        if (!_exists(tokenId)) revert TokenNotExists();
        
        // Verify oracle signature
        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, newImageURI, block.timestamp));
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();
        
        if (usedSignatures[ethSignedHash]) revert SignatureAlreadyUsed();
        if (ethSignedHash.recover(signature) != metadataOracle) revert InvalidSignature();
        
        usedSignatures[ethSignedHash] = true;
        bioData[tokenId].currentImageURI = newImageURI;
        
        // Check for evolution trigger
        uint256 growthStage = _getCurrentGrowthStage(tokenId);
        stageImageURIs[tokenId][growthStage] = newImageURI;
        
        emit MetadataUpdated(tokenId, newImageURI);
        emit EvolutionTriggered(tokenId, growthStage);
    }
    
    /**
     * @notice Breeds two BioNFTs to create offspring
     * @param parentTokenId1 First parent token
     * @param parentTokenId2 Second parent token
     * @param growthTrackerId New organism ID from GrowthTracker
     * @return offspringTokenId The new offspring token ID
     */
    function breed(
        uint256 parentTokenId1,
        uint256 parentTokenId2,
        uint256 growthTrackerId
    ) external returns (uint256 offspringTokenId) {
        require(ownerOf(parentTokenId1) == msg.sender, "Not owner of parent 1");
        require(ownerOf(parentTokenId2) == msg.sender, "Not owner of parent 2");
        require(
            keccak256(bytes(bioData[parentTokenId1].species)) == 
            keccak256(bytes(bioData[parentTokenId2].species)),
            "Species mismatch"
        );
        
        offspringTokenId = nextTokenId++;
        
        GeneticProfile memory offspring = _crossGenetics(
            bioData[parentTokenId1].genetics,
            bioData[parentTokenId2].genetics
        );
        offspring.generation = bioData[parentTokenId1].genetics.generation + 1;
        
        bioData[offspringTokenId] = BioMetadata({
            species: bioData[parentTokenId1].species,
            growthTrackerId: growthTrackerId,
            parentId1: parentTokenId1,
            parentId2: parentTokenId2,
            birthTimestamp: block.timestamp,
            genetics: offspring,
            currentImageURI: _getInitialImageURI(bioData[parentTokenId1].species)
        });
        
        _safeMint(msg.sender, offspringTokenId);
        
        emit BioNFTMinted(offspringTokenId, msg.sender, growthTrackerId, bioData[parentTokenId1].species);
        emit GeneticsRevealed(offspringTokenId, offspring);
    }
    
    /**
     * @notice Gets complete organism data including growth metrics
     * @param tokenId Token to query
     * @return species The organism species
     * @return stage Current growth stage
     * @return health Current health score
     * @return biomass Current biomass
     * @return genetics Genetic profile
     */
    function getOrganismData(uint256 tokenId) external view returns (
        string memory species,
        uint256 stage,
        uint256 health,
        uint256 biomass,
        GeneticProfile memory genetics
    ) {
        if (!_exists(tokenId)) revert TokenNotExists();
        
        BioMetadata memory data = bioData[tokenId];
        species = data.species;
        genetics = data.genetics;
        
        // Get current metrics from GrowthTracker
        (stage, health, biomass) = growthTracker.getCurrentMetrics(data.growthTrackerId);
    }
    
    /**
     * @notice Returns the metadata URI for a token
     * @param tokenId Token to query
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        if (!_exists(tokenId)) revert TokenNotExists();
        
        // Generate dynamic metadata based on current state
        BioMetadata memory data = bioData[tokenId];
        (uint256 stage, uint256 health, uint256 biomass) = growthTracker.getCurrentMetrics(data.growthTrackerId);
        
        // Return on-chain metadata
        string memory json = string(abi.encodePacked(
            '{"name":"', data.species, ' #', tokenId.toString(), '",',
            '"description":"A living ', data.species, ' organism in the Spore Protocol ecosystem.",',
            '"image":"', data.currentImageURI, '",',
            '"attributes":[',
                '{"trait_type":"Species","value":"', data.species, '"},',
                '{"trait_type":"Generation","value":', uint256(data.genetics.generation).toString(), '},',
                '{"trait_type":"Growth Stage","value":', stage.toString(), '},',
                '{"trait_type":"Health","value":', health.toString(), '},',
                '{"trait_type":"Biomass","value":', biomass.toString(), '},',
                '{"trait_type":"Growth Speed","value":', uint256(data.genetics.growthSpeed).toString(), '},',
                '{"trait_type":"Disease Resistance","value":', uint256(data.genetics.diseaseResistance).toString(), '},',
                '{"trait_type":"Yield Potential","value":', uint256(data.genetics.yieldPotential).toString(), '},',
                '{"trait_type":"Adaptability","value":', uint256(data.genetics.adaptability).toString(), '},',
                '{"trait_type":"Rarity","value":"', _getRarityString(data.genetics.rarity), '"}',
            ']}'
        ));
        
        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(json))));
    }
    
    // Internal functions
    
    function _generateGenetics(uint256[2] memory parentIds) private view returns (GeneticProfile memory) {
        GeneticProfile memory genetics;
        
        if (parentIds[0] == 0 && parentIds[1] == 0) {
            // Genesis generation - random genetics
            uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, nextTokenId)));
            
            genetics.growthSpeed = uint16((seed % 4000) + 3000); // 3000-7000
            genetics.diseaseResistance = uint16(((seed >> 16) % 4000) + 3000);
            genetics.yieldPotential = uint16(((seed >> 32) % 4000) + 3000);
            genetics.adaptability = uint16(((seed >> 48) % 4000) + 3000);
            genetics.generation = 0;
            genetics.rarity = _calculateRarity(genetics);
        } else {
            // Inherited genetics
            genetics = _crossGenetics(
                bioData[parentIds[0]].genetics,
                bioData[parentIds[1]].genetics
            );
        }
        
        return genetics;
    }
    
    function _crossGenetics(
        GeneticProfile memory parent1,
        GeneticProfile memory parent2
    ) private view returns (GeneticProfile memory offspring) {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, nextTokenId)));
        
        // Mendelian inheritance with mutations
        offspring.growthSpeed = _inheritTrait(parent1.growthSpeed, parent2.growthSpeed, seed);
        offspring.diseaseResistance = _inheritTrait(parent1.diseaseResistance, parent2.diseaseResistance, seed >> 32);
        offspring.yieldPotential = _inheritTrait(parent1.yieldPotential, parent2.yieldPotential, seed >> 64);
        offspring.adaptability = _inheritTrait(parent1.adaptability, parent2.adaptability, seed >> 96);
        offspring.generation = parent1.generation + 1;
        offspring.rarity = _calculateRarity(offspring);
    }
    
    function _inheritTrait(uint16 trait1, uint16 trait2, uint256 seed) private pure returns (uint16) {
        uint16 avgTrait = (trait1 + trait2) / 2;
        
        // 10% chance of mutation
        if (seed % 10 == 0) {
            // Mutation can be +/- 10%
            int16 mutation = int16(uint16(seed % 2000)) - 1000;
            int32 newTrait = int32(uint32(avgTrait)) + int32(mutation);
            
            // Clamp between 0 and 10000
            if (newTrait < 0) newTrait = 0;
            if (newTrait > 10000) newTrait = 10000;
            
            return uint16(uint32(newTrait));
        }
        
        return avgTrait;
    }
    
    function _calculateRarity(GeneticProfile memory genetics) private pure returns (uint8) {
        uint256 totalScore = genetics.growthSpeed + genetics.diseaseResistance + 
                           genetics.yieldPotential + genetics.adaptability;
        
        if (totalScore >= 35000) return 5; // Legendary
        if (totalScore >= 30000) return 4; // Epic  
        if (totalScore >= 25000) return 3; // Rare
        if (totalScore >= 20000) return 2; // Uncommon
        if (totalScore >= 15000) return 1; // Common
        return 0; // Basic
    }
    
    function _getRarityString(uint8 rarity) private pure returns (string memory) {
        if (rarity == 5) return "Legendary";
        if (rarity == 4) return "Epic";
        if (rarity == 3) return "Rare";
        if (rarity == 2) return "Uncommon";
        if (rarity == 1) return "Common";
        return "Basic";
    }
    
    function _getCurrentGrowthStage(uint256 tokenId) private view returns (uint256) {
        BioMetadata memory data = bioData[tokenId];
        (uint256 stage,,) = growthTracker.getCurrentMetrics(data.growthTrackerId);
        return stage;
    }
    
    function _getInitialImageURI(string memory species) private view returns (string memory) {
        return string(abi.encodePacked(baseURI, "/", species, "/seed.png"));
    }
    
    function _base64Encode(bytes memory data) private pure returns (string memory) {
        // Base64 encoding implementation
        // This is a simplified version - in production use a library
        return string(data);
    }
    
    // Required overrides
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
        delete bioData[tokenId];
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    
    // Admin functions
    
    function setBaseURI(string memory _baseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _baseURI;
    }
    
    function setMetadataOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        metadataOracle = _oracle;
    }
    
    function setEvolutionThreshold(
        string memory species,
        uint256 stage,
        uint256 threshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        evolutionThresholds[species][stage] = threshold;
    }
}