// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; // Fixed: Changed from <0.9.0 to ^0.8.19

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ActivateEarthNFT
 * @dev Contract for minting and managing NFTs with multiple types and user levels
 * @custom:security-contact security@activateearth.com
 */
contract ActivateEarthNFT is ERC721URIStorage, Ownable, Pausable, ReentrancyGuard {
    // State variables
    uint256 private _tokenIdCounter = 1;
    bytes32 private _merkleRoot;
    address private _guard1;
    address private _guard2;
    uint8 private _nftTypeCounter;
    bool private _guardDecision;

    // EVENTS
    event NFTTypeAdded(uint8 indexed id, string name, uint256 price, uint256 maxSupply, uint8 maxPoolNumber, string baseURI);
    event NFTMinted(address indexed to, uint256 indexed tokenId, uint8 nftTypeIndex);
    event NFTTypeUpdated(uint8 indexed id, string name, uint256 price, uint256 maxSupply, uint8 maxPoolNumber, string baseURI, bool isActive);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event MerkleRootUpdated(bytes32 newRoot);

    // STRUCTS
    struct NFTType {
        uint8 id;
        string name;
        uint256 price;
        uint256 maxSupply;
        uint256 currentSupply;
        uint8 maxPoolNumber;
        string baseURI;
        bool isActive;
        uint16 freeMintNumber;
    }
    
    struct NftTypeInput {
        string name;
        string baseURI;
        uint256 price;
        uint256 maxSupply;
        uint8 maxPoolNumber;
        uint16 freeMintNumber;
    }

    // MAPPINGS
    mapping(uint8 => NFTType) public nftTypes;
    mapping(address => mapping(uint8 => bool)) public hasUserMinted;
    mapping(address => uint8) public userLevel;   
    mapping(address => bool) public guardDecisions;
    mapping(address => mapping(uint8 => bool)) public hasFreeMinted;
    mapping(address => bool) public hasWhitelistMinted; // Fixed: Single whitelist mint per user

    // MODIFIERS
    modifier validNFTType(uint8 _nftTypeIndex) {    
        require(_nftTypeIndex < _nftTypeCounter, "Invalid type index");
        require(bytes(nftTypes[_nftTypeIndex].name).length > 0, "NFT type does not exist");
        _;
    }

    modifier validNFTInputs(NftTypeInput memory _input) {
        require(bytes(_input.name).length > 0 && bytes(_input.name).length <= 50, "Name length invalid");
        require(bytes(_input.baseURI).length > 0, "Empty base URI");
        require(_input.maxSupply > 0, "Supply must be greater than zero");
        require(_input.maxPoolNumber > 0, "Pool number must be greater than zero");
        require(_input.freeMintNumber <= _input.maxSupply, "Free mint exceeds supply");
        _;
    }

    modifier onlyGuard() {
        require(msg.sender == _guard1 || msg.sender == _guard2, "Caller is not guard");
        _;
    }

    /**
     * @dev Constructor initializes the contract with name and symbol
     */
    constructor(
        address guard1, 
        address guard2,
        bytes32 merkleRoot
    ) ERC721("ActivateEarthNFT", "AENFT") Ownable(msg.sender) {
        require(guard1 != address(0) && guard2 != address(0), "Guard addresses cannot be zero");
        _guard1 = guard1;
        _guard2 = guard2;
        _merkleRoot = merkleRoot;
    }   

    /**
     * @dev Add a new NFT Type
     */
    function addNftType(
        NftTypeInput memory _input
    ) external onlyOwner validNFTInputs(_input) nonReentrant {
        uint8 currentTypeId = _nftTypeCounter;
        _nftTypeCounter++;
        
        nftTypes[currentTypeId] = NFTType({
            id: currentTypeId,
            name: _input.name,
            price: _input.price,
            maxSupply: _input.maxSupply,
            currentSupply: 0,
            maxPoolNumber: _input.maxPoolNumber,
            baseURI: _input.baseURI,
            isActive: true,
            freeMintNumber: _input.freeMintNumber
        });
        
        emit NFTTypeAdded(currentTypeId, _input.name, _input.price, _input.maxSupply, _input.maxPoolNumber, _input.baseURI);
    }

    /**
     * @dev Update NFT type
     */
    function updateNftType(
        uint8 _nftTypeIndex, 
        NftTypeInput memory _input,
        bool _isActive
    ) external onlyOwner validNFTType(_nftTypeIndex) validNFTInputs(_input) nonReentrant {
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        
        nftType.name = _input.name;
        nftType.price = _input.price;
        nftType.maxSupply = _input.maxSupply;
        nftType.maxPoolNumber = _input.maxPoolNumber;
        nftType.baseURI = _input.baseURI;
        nftType.freeMintNumber = _input.freeMintNumber;
        nftType.isActive = _isActive;

        emit NFTTypeUpdated(_nftTypeIndex, _input.name, _input.price, _input.maxSupply, _input.maxPoolNumber, _input.baseURI, _isActive);
    }

    /**
     * @dev Update NFT type active status
     */
    function updateNftTypeStatus(uint8 _nftTypeIndex, bool _isActive) external onlyOwner validNFTType(_nftTypeIndex) {
        nftTypes[_nftTypeIndex].isActive = _isActive;
        
        NFTType memory nftType = nftTypes[_nftTypeIndex];
        emit NFTTypeUpdated(_nftTypeIndex, nftType.name, nftType.price, nftType.maxSupply, nftType.maxPoolNumber, nftType.baseURI, _isActive);
    }

    /**
     * @dev Set merkle root for whitelist
     */
    function setMerkleRoot(bytes32 _newMerkleRoot) external onlyOwner {
        _merkleRoot = _newMerkleRoot;
        emit MerkleRootUpdated(_newMerkleRoot);
    }

    /**
     * @dev Whitelist mint function - Fixed version
     */
    function whitelistMint(bytes32[] calldata merkleProof, uint8 _nftTypeIndex) 
        external 
        whenNotPaused 
        nonReentrant 
        validNFTType(_nftTypeIndex) 
    {
        require(!hasWhitelistMinted[msg.sender], "Already whitelist minted");
        
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        require(nftType.isActive, "NFT type not active");
        require(nftType.currentSupply < nftType.maxSupply, "Max supply reached");
        require(!hasUserMinted[msg.sender][_nftTypeIndex], "Already minted this type");

        // Merkle proof verification
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, _merkleRoot, leaf), "Invalid proof");
        
        // Mark as whitelist minted
        hasWhitelistMinted[msg.sender] = true;
        hasUserMinted[msg.sender][_nftTypeIndex] = true;

        // Mint NFT
        _safeMint(msg.sender, _tokenIdCounter);
        _setTokenURI(_tokenIdCounter, nftType.baseURI);
        
        // Update user level
        if (_nftTypeIndex > userLevel[msg.sender]) {
            userLevel[msg.sender] = _nftTypeIndex;
        }
        
        // Update counters
        nftType.currentSupply++;
        _tokenIdCounter++;
        
        emit NFTMinted(msg.sender, _tokenIdCounter - 1, _nftTypeIndex);
    }

    /**
     * @dev Regular mint function - Fixed version
     */
    function mint(uint8 _nftTypeIndex) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
        validNFTType(_nftTypeIndex) 
    {
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        
        require(nftType.isActive, "NFT type not active");
        require(nftType.currentSupply < nftType.maxSupply, "Max supply reached");
        require(!hasUserMinted[msg.sender][_nftTypeIndex], "Already minted this type");

        bool isFree = false;
        
        // Check if user can get free mint
        if (nftType.freeMintNumber > 0 && !hasFreeMinted[msg.sender][_nftTypeIndex]) {
            isFree = true;
            nftType.freeMintNumber--;
            hasFreeMinted[msg.sender][_nftTypeIndex] = true;
        }

        // Check payment if not free
        if (!isFree) {
            require(msg.value >= nftType.price, "Insufficient payment");
        }

        // Mint NFT
        _safeMint(msg.sender, _tokenIdCounter);
        _setTokenURI(_tokenIdCounter, nftType.baseURI);
        
        hasUserMinted[msg.sender][_nftTypeIndex] = true;
        
        // Update user level
        if (_nftTypeIndex > userLevel[msg.sender]) {
            userLevel[msg.sender] = _nftTypeIndex;
        }

        // Update counters
        nftType.currentSupply++;
        _tokenIdCounter++;
        
        emit NFTMinted(msg.sender, _tokenIdCounter - 1, _nftTypeIndex);
    }

// 124 194 205 238 235


    /**
     * @dev Withdraw funds - requires both guards' approval
     */
    function withdraw() external onlyOwner nonReentrant {
        require(_guardDecision, "Not approved by guards");
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");
        
        // Reset guard decisions after withdrawal
        resetGuardDecisions();
        
        (bool success, ) = payable(owner()).call{value: contractBalance}("");
        require(success, "Transfer failed");
        
        emit FundsWithdrawn(owner(), contractBalance);
    }

    // *** GETTER FUNCTIONS ***
    function getUserOwnedNFT(uint8 _nftTypeIndex) external view validNFTType(_nftTypeIndex) returns (bool) {
        return hasUserMinted[msg.sender][_nftTypeIndex];
    }

    function getUserLevel(address user) external view returns (uint8) {
        return userLevel[user];
    }

    function getNftTypes() external view returns (NFTType[] memory) {
        NFTType[] memory nfts = new NFTType[](_nftTypeCounter);
        for(uint8 i = 0; i < _nftTypeCounter; i++) {
            nfts[i] = nftTypes[i];
        }
        return nfts;
    }

    function getNftType(uint8 _nftTypeIndex) external view validNFTType(_nftTypeIndex) returns (NFTType memory) {
        return nftTypes[_nftTypeIndex];
    }

    function getNftTypeBaseURI(uint8 _nftTypeIndex) external view validNFTType(_nftTypeIndex) returns (string memory) {
        return nftTypes[_nftTypeIndex].baseURI;
    }

    function getNftTypeCounter() external view returns (uint8) {
        return _nftTypeCounter;
    }

    function getTokenIdCounter() external view onlyOwner returns(uint256) {
        return _tokenIdCounter;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    // *** ADMIN FUNCTIONS ***
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // *** GUARD FUNCTIONS ***
    function guardPass(bool decision) external nonReentrant onlyGuard returns (bool) {
        guardDecisions[msg.sender] = decision;
        _guardDecision = guardDecisions[_guard1] && guardDecisions[_guard2];
        return _guardDecision;
    }

    function resetGuardDecisions() private {
        guardDecisions[_guard1] = false;
        guardDecisions[_guard2] = false;
        _guardDecision = false;
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Renouncing ownership is disabled");
    }
    
    function transferOwnership(address newOwner) public override onlyGuard nonReentrant {
        require(_guardDecision, "Not approved by guards");
        require(newOwner != address(0), "Invalid new owner");
        
        resetGuardDecisions();
        _transferOwnership(newOwner);  
    }

    // *** FALLBACK FUNCTIONS ***
    fallback() external payable {}
    receive() external payable {}
}