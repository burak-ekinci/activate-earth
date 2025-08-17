// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ActivateEarthNFT
 * @dev Enhanced NFT contract with multiple types, whitelist, and guard system
 * @notice This contract manages multiple NFT types with different properties and user levels
 * @custom:security-contact security@activateearth.com
 */
contract ActivateEarthNFT is ERC721URIStorage, Ownable, Pausable, ReentrancyGuard {
    
    // ============ STATE VARIABLES ============
    uint256 private _tokenIdCounter = 1;
    bytes32 private _merkleRoot;
    address private _guard1;
    address private _guard2;
    uint8 private _nftTypeCounter;
    bool private _guardDecision;
    
    // ============ EVENTS ============
    event NFTTypeAdded(
        uint8 indexed id, 
        string name, 
        uint256 price, 
        uint256 maxSupply, 
        uint8 maxPoolNumber, 
        string baseURI
    );
    event NFTMinted(
        address indexed to, 
        uint256 indexed tokenId, 
        uint8 nftTypeIndex
    );
    event NFTTypeUpdated(
        uint8 indexed id, 
        string name, 
        uint256 price, 
        uint256 maxSupply, 
        uint8 maxPoolNumber, 
        string baseURI, 
        bool isActive
    );
    event FundsWithdrawn(address indexed to, uint256 amount);
    event MerkleRootUpdated(bytes32 newRoot);
    event GuardDecision(address indexed guard, bool decision);

    // ============ STRUCTS ============
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

    // ============ CUSTOM ERRORS ============
    error InvalidTypeIndex();
    error NftTypeDoesNotExist();
    error NameLengthInvalid();
    error PriceCannotBeZero();
    error SupplyMustBePositive();
    error PoolNumberMustBePositive();
    error EmptyBaseURI();
    error FreeMintExceedsSupply();
    error CallerIsNotGuard();
    error InvalidGuardAddress();
    error MaxSupplyReached();
    error NFTTypeNotActive();
    error AlreadyMinted();
    error InvalidProof();
    error InsufficientPayment();
    error NoFundsToWithdraw();
    error TransferFailed();
    error NotApprovedByGuards();
    error MerkleRootCannotBeZero();
    error NewOwnerInvalid();
    
    // ============ MAPPINGS ============
    mapping(uint8 => NFTType) public nftTypes;
    mapping(address => uint8) public userLevel;
    mapping(address => bool) public guardDecisions;
    mapping(address => mapping(uint8 => bool)) public hasUserMinted;
    mapping(address => bool) public hasWhitelistMinted; // Sadece bir kez whitelist mint
    mapping(address => mapping(uint8 => bool)) public hasFreeMinted;

    // ============ MODIFIERS ============
    modifier validNFTType(uint8 _nftTypeIndex) {
        if (_nftTypeIndex > _nftTypeCounter || _nftTypeIndex < 1) revert InvalidTypeIndex();
        if (bytes(nftTypes[_nftTypeIndex].name).length == 0) revert NftTypeDoesNotExist();
        _;
    }

    modifier validNFTInputs(NftTypeInput memory _input) {
        if (bytes(_input.name).length == 0 || bytes(_input.name).length > 50) revert NameLengthInvalid();
        if (bytes(_input.baseURI).length == 0) revert EmptyBaseURI();
        if (_input.maxSupply == 0) revert SupplyMustBePositive();
        if (_input.maxPoolNumber == 0) revert PoolNumberMustBePositive();
        if (_input.freeMintNumber > _input.maxSupply) revert FreeMintExceedsSupply();
        _;
    }

    modifier onlyGuard() {
        if (msg.sender != _guard1 && msg.sender != _guard2) revert CallerIsNotGuard();
        _;
    }

    // ============ CONSTRUCTOR ============
    /**
     * @dev Initializes the contract with guard addresses
     * @param guard1 First guard address
     * @param guard2 Second guard address
     */
    constructor(
        address guard1, 
        address guard2
    ) ERC721("ActivateEarthNFT", "AENFT") Ownable(msg.sender) {
        if (guard1 == address(0) || guard2 == address(0)) revert InvalidGuardAddress();
        if (guard1 == guard2) revert InvalidGuardAddress();
        
        _guard1 = guard1;
        _guard2 = guard2;
        _nftTypeCounter = 0;
    }

    // ============ MAIN FUNCTIONS ============
    
    /**
     * @dev Add a new NFT Type
     * @param _input NFT type input parameters
     */
    function addNftType(
        NftTypeInput memory _input
    ) external onlyOwner validNFTInputs(_input) nonReentrant {
        _nftTypeCounter++;
        uint8 currentTypeId = _nftTypeCounter;
        
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
        
        
        emit NFTTypeAdded(
            currentTypeId, 
            _input.name, 
            _input.price, 
            _input.maxSupply, 
            _input.maxPoolNumber, 
            _input.baseURI
        );
    }

    /**
     * @dev Update existing NFT type
     * @param _nftTypeIndex Index of NFT type to update
     * @param _input New input parameters
     * @param _isActive New active status
     */
    function updateNftType(
        uint8 _nftTypeIndex,
        NftTypeInput memory _input,
        bool _isActive
    ) external onlyOwner validNFTType(_nftTypeIndex) validNFTInputs(_input) nonReentrant {
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        
        // Max supply sadece artırılabilir
        if (_input.maxSupply < nftType.currentSupply) revert SupplyMustBePositive();
        
        nftType.name = _input.name;
        nftType.price = _input.price;
        nftType.maxSupply = _input.maxSupply;
        nftType.maxPoolNumber = _input.maxPoolNumber;
        nftType.baseURI = _input.baseURI;
        nftType.freeMintNumber = _input.freeMintNumber;
        nftType.isActive = _isActive;

        emit NFTTypeUpdated(
            _nftTypeIndex, 
            _input.name, 
            _input.price, 
            _input.maxSupply, 
            _input.maxPoolNumber, 
            _input.baseURI, 
            _isActive
        );
    }

    /**
     * @dev Update NFT type active status only
     * @param _nftTypeIndex Index of NFT type
     * @param _isActive New active status
     */
    function updateNftTypeStatus(
        uint8 _nftTypeIndex, 
        bool _isActive
    ) external onlyOwner validNFTType(_nftTypeIndex) {
        nftTypes[_nftTypeIndex].isActive = _isActive;
        
        NFTType memory nftType = nftTypes[_nftTypeIndex];
        emit NFTTypeUpdated(
            _nftTypeIndex, 
            nftType.name, 
            nftType.price, 
            nftType.maxSupply, 
            nftType.maxPoolNumber, 
            nftType.baseURI, 
            _isActive
        );
    }

    /**
     * @dev Whitelist mint - only once per user
     * @param merkleProof Merkle proof for whitelist verification
     * @param _nftTypeIndex NFT type to mint
     */
    function whitelistMint(
        bytes32[] calldata merkleProof, 
        uint8 _nftTypeIndex
    ) external whenNotPaused nonReentrant validNFTType(_nftTypeIndex) {
        if (hasWhitelistMinted[msg.sender]) revert AlreadyMinted();
        
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        if (!nftType.isActive) revert NFTTypeNotActive();
        if (nftType.currentSupply >= nftType.maxSupply) revert MaxSupplyReached();
        if (hasUserMinted[msg.sender][_nftTypeIndex]) revert AlreadyMinted();

        // Check if merkle root is set
        if (_merkleRoot == bytes32(0)) revert MerkleRootCannotBeZero();
        
        // Merkle proof verification
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(merkleProof, _merkleRoot, leaf)) revert InvalidProof();
        
        // Update states
        hasWhitelistMinted[msg.sender] = true;
        hasUserMinted[msg.sender][_nftTypeIndex] = true;

        // Mint NFT
        _mintNFT(msg.sender, _nftTypeIndex, nftType);
    }

    /**
     * @dev Regular mint function with free mint support
     * @param _nftTypeIndex NFT type to mint
     */
    function mint(
        uint8 _nftTypeIndex
    ) external payable whenNotPaused nonReentrant validNFTType(_nftTypeIndex) {
        NFTType storage nftType = nftTypes[_nftTypeIndex];
        
        if (!nftType.isActive) revert NFTTypeNotActive();
        if (nftType.currentSupply >= nftType.maxSupply) revert MaxSupplyReached();
        if (hasUserMinted[msg.sender][_nftTypeIndex]) revert AlreadyMinted();

        bool isFree = false;
        
        // Check if user can get free mint
        if (nftType.freeMintNumber > 0 && !hasFreeMinted[msg.sender][_nftTypeIndex]) {
            isFree = true;
            // Safe decrement with underflow protection
            unchecked {
                nftType.freeMintNumber = nftType.freeMintNumber - 1;
            }
            hasFreeMinted[msg.sender][_nftTypeIndex] = true;
        }

        // Check payment if not free
        if (!isFree) {
            if (msg.value < nftType.price) revert InsufficientPayment();
        }

        // Update user minted status
        hasUserMinted[msg.sender][_nftTypeIndex] = true;
        
        // Mint NFT
        _mintNFT(msg.sender, _nftTypeIndex, nftType);
    }

    /**
     * @dev Internal mint function
     * @param to Address to mint to
     * @param nftTypeIndex NFT type index
     * @param nftType NFT type storage reference
     */
    function _mintNFT(
        address to, 
        uint8 nftTypeIndex, 
        NFTType storage nftType
    ) internal {
        uint256 tokenId = _tokenIdCounter;
        
        // Mint NFT with URI
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, nftType.baseURI);
        
        // Update user level
        if (nftTypeIndex > userLevel[to]) {
            userLevel[to] = nftTypeIndex;
        }
        
        // Update counters
        nftType.currentSupply++;
        _tokenIdCounter++;
        
        emit NFTMinted(to, tokenId, nftTypeIndex);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Set merkle root for whitelist
     * @param _newMerkleRoot New merkle root
     */
    function setMerkleRoot(bytes32 _newMerkleRoot) external onlyOwner {
        if (_newMerkleRoot == bytes32(0)) revert MerkleRootCannotBeZero();
        _merkleRoot = _newMerkleRoot;
        emit MerkleRootUpdated(_newMerkleRoot);
    }

    /**
     * @dev Withdraw funds - requires guard approval
     */
    function withdraw() external onlyOwner nonReentrant {
        if (!_guardDecision) revert NotApprovedByGuards();
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0) revert NoFundsToWithdraw();
        
        // Reset guard decisions
        _resetGuardDecisions();
        
        (bool success, ) = payable(owner()).call{value: contractBalance}("");
        if (!success) revert TransferFailed();
        
        emit FundsWithdrawn(owner(), contractBalance);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ GUARD FUNCTIONS ============

    /**
     * @dev Guard decision for critical operations
     * @param decision Guard's decision
     */
    function guardPass(bool decision) external nonReentrant onlyGuard returns (bool) {
        guardDecisions[msg.sender] = decision;
        _guardDecision = guardDecisions[_guard1] && guardDecisions[_guard2];
        
        emit GuardDecision(msg.sender, decision);
        return _guardDecision;
    }

    /**
     * @dev Reset guard decisions - internal function
     */
    function _resetGuardDecisions() internal {
        guardDecisions[_guard1] = false;
        guardDecisions[_guard2] = false;
        _guardDecision = false;
    }

    /**
     * @dev Transfer ownership with guard approval - can be called by owner or guards
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) public override nonReentrant {
        // Either owner can call (with guard approval) or guards can call directly
        if (msg.sender != owner() && msg.sender != _guard1 && msg.sender != _guard2) {
            revert("Caller must be owner or guard");
        }
        
        // If called by owner, require guard approval
        if (msg.sender == owner() && !_guardDecision) revert NotApprovedByGuards();
        
        if (newOwner == address(0)) revert NewOwnerInvalid();
        
        _resetGuardDecisions();
        _transferOwnership(newOwner);
    }

    /**
     * @dev Disable renouncing ownership
     */
    function renounceOwnership() public view override onlyOwner {
        revert("Renouncing ownership disabled");
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Check if user owns specific NFT type
     * @param user User address
     * @param _nftTypeIndex NFT type index
     */
    function getUserOwnedNFT(
        address user, 
        uint8 _nftTypeIndex
    ) external view validNFTType(_nftTypeIndex) returns (bool) {
        return hasUserMinted[user][_nftTypeIndex];
    }

    /**
     * @dev Get all NFT types
     */
    function getNftTypes() external view returns (NFTType[] memory) {
        NFTType[] memory nfts = new NFTType[](_nftTypeCounter);
        for (uint8 i = 0; i < _nftTypeCounter; i++) {
            nfts[i] = nftTypes[i+1];
        }
        return nfts;
    }

    /**
     * @dev Get NFT type base URI
     * @param _nftTypeIndex NFT type index
     */
    function getNftTypeBaseURI(
        uint8 _nftTypeIndex
    ) external view validNFTType(_nftTypeIndex) returns (string memory) {
        return nftTypes[_nftTypeIndex].baseURI;
    }

    /**
     * @dev Get total NFT type count
     */
    function getNftTypeCounter() external view returns (uint8) {
        return _nftTypeCounter;
    }

    /**
     * @dev Get current token ID counter - only owner
     */
    function getTokenIdCounter() external view onlyOwner returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Get current merkle root
     */
    function getMerkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    /**
     * @dev Get guard addresses
     */
    function getGuards() external view returns (address, address) {
        return (_guard1, _guard2);
    }

    /**
     * @dev Get current guard decision status
     */
    function getGuardDecision() external view returns (bool) {
        return _guardDecision;
    }

    // ============ FALLBACK FUNCTIONS ============
    
    /**
     * @dev Fallback function to receive ETH
     */
    fallback() external payable {}

    /**
     * @dev Receive function to receive ETH
     */
    receive() external payable {}
}
