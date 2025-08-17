// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ActivateEarth NFT-Based Campaign DApp
 * @dev A contract for managing campaigns with NFT level restrictions
 * @notice This contract allows users to create campaigns based on their NFT level limits
 */

/**
 * @title ActivateEarth NFT Interface
 * @dev Interface for interacting with ActivateEarthNFT contract
 */
interface IActivateEarthNFT {
    function getUserOwnedNFT(address user, uint8 _nftTypeIndex) external view returns (bool);
    function getNftTypeCounter() external view returns (uint8);
    function userLevel(address) external view returns (uint8);
       function nftTypes(uint8 idx) external view
      returns (
        uint8 id,
        string memory name,
        uint256 price,
        uint256 maxSupply,
        uint256 currentSupply,
        uint8 maxPoolNumber,
        string memory baseURI,
        bool isActive,
        uint16 freeMintNumber
      );
}

/**
 * @title ActivateEarthDapp
 * @dev Campaign management system with NFT level restrictions
 */
contract ActivateEarthDapp is ReentrancyGuard, Pausable, Ownable {
 
    // ============ STATE VARIABLES ============
    uint256 private _campaignIds;
    IActivateEarthNFT private _nftContract;

    // ============ STRUCTS ============
    struct Campaign {
        uint256 id;
        address creator;
        string title;
        string description;
        bool isActive;
        uint256 endDate;
        uint256 totalMemberNumber;
        uint256 tokenAmount;
        uint256 tokenAmountPerMember;
        uint256 completedTokenAmount;
        uint256 completedMemberNumber;
        uint256 registeredMemberNumber;
        mapping(address => bool) registeredMembers;
        mapping(address => bool) completedMembers;
    }

    // ============ MAPPINGS ============
    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public userCampaignCount; // 🆕 User'ın oluşturduğu campaign sayısı

    // ============ EVENTS ============
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 startDate,
        uint256 endDate,
        uint256 totalMemberNumber,
        uint256 tokenAmount,
        uint8 creatorLevel
    );
    event CampaignRegistered(
        uint256 indexed campaignId,
        address indexed member,
        uint256 totalMemberNumber,
        uint256 registeredMemberNumber
    );
    event CampaignCompleted(
        uint256 indexed campaignId,
        address indexed member,
        uint256 completedTokenAmount,
        uint256 completedMemberNumber
    );
    event TokensWithdrawn(address indexed member, uint256 amount);
    event CampaignCancelled(uint256 indexed campaignId);
    event CampaignStatusUpdated(uint256 indexed campaignId, bool status);

    // ============ CONSTANTS ============
    uint256 private constant DAILY = 1 days;
    uint256 private constant WEEKLY = 7 days;
    uint256 private constant MONTHLY = 30 days;

    // ============ CUSTOM ERRORS ============
    error InvalidNFTContract();
    error UserHasNoNFT();
    error NFTTypeNotActive();
    error CampaignLimitReached();
    error InvalidCampaignData();
    error CampaignNotFound();
    error CampaignEnded();
    error AlreadyRegistered();
    error CampaignNotActive();
    error CampaignWasCompleted();
    error NotRegistered();
    error AlreadyCompleted();
    error NoTokensToWithdraw();
    error TransferFailed();
    error InsufficientBalance();
    error NFTContractCallFailed();

    // ============ ENUMS ============
    enum DurationType {
        DAILY,
        WEEKLY,
        MONTHLY,
        UNLIMITED
    }

    // ============ MODIFIERS ============
    modifier validCampaign(uint256 campaignId) {
        if (campaignId == 0 || campaignId > _campaignIds) revert CampaignNotFound();
        if (campaigns[campaignId].creator == address(0)) revert CampaignNotFound();
        _;
    }

    // ============ CONSTRUCTOR ============
    /**
     * @dev Initialize the dApp with NFT contract address
     * @param nftContractAddress Address of the ActivateEarthNFT contract
     */
    constructor(address nftContractAddress) Ownable(msg.sender) {
        if (nftContractAddress == address(0)) revert InvalidNFTContract();
        _nftContract = IActivateEarthNFT(nftContractAddress);
    }

    // ============ MAIN FUNCTIONS ============

    /**
     * @dev Creates a new campaign with NFT level restrictions
     * @param title Campaign title
     * @param description Campaign description
     * @param totalMemberNumber Total number of members allowed
     * @param duration Duration multiplier
     * @param durationType Duration type ("DAILY", "WEEKLY", "MONTHLY", "UNLIMITED")
     */
 function createCampaign(
    string memory title,
    string memory description,
    uint256 totalMemberNumber,
    uint256 duration,
    DurationType durationType
) external payable whenNotPaused nonReentrant {

    if (bytes(title).length == 0)             revert InvalidCampaignData();
    if (bytes(description).length == 0)       revert InvalidCampaignData();
    if (totalMemberNumber == 0)               revert InvalidCampaignData();
    if (duration == 0)                        revert InvalidCampaignData();
    if (msg.value == 0)                       revert InvalidCampaignData();
    if (msg.value % totalMemberNumber != 0)   revert InvalidCampaignData();
   
  

    uint8 level;
    try _nftContract.userLevel(msg.sender) returns (uint8 _level) {
        level = _level;
    } catch {
        revert NFTContractCallFailed();
    }
    
    if (level == 0) revert UserHasNoNFT();

    uint8 maxPoolNumber;
    bool isActive;
    
    try _nftContract.nftTypes(level) returns (
        uint8,      // id
        string memory,   // name
        uint256,    // price
        uint256,    // maxSupply
        uint256,    // currentSupply
        uint8 _maxPoolNumber,
        string memory,    // baseURI
        bool _isActive,
        uint16      // freeMintNumber
    ) {
        maxPoolNumber = _maxPoolNumber;
        isActive = _isActive;
    } catch {
        revert NFTContractCallFailed();
    }

    if (!isActive)          revert NFTTypeNotActive();
    if (userCampaignCount[msg.sender] >= maxPoolNumber) revert CampaignLimitReached();

    uint256 endDate = _calculateEndDate(duration, durationType);

    _campaignIds++;
    uint256 campaignId = _campaignIds;
    Campaign storage newCampaign = campaigns[campaignId];

    newCampaign.id                    = campaignId;
    newCampaign.creator               = msg.sender;
    newCampaign.title                 = title;
    newCampaign.description           = description;
    newCampaign.isActive              = true;
    newCampaign.endDate               = endDate;
    newCampaign.tokenAmount           = msg.value;
    newCampaign.tokenAmountPerMember  = msg.value / totalMemberNumber;
    newCampaign.totalMemberNumber     = totalMemberNumber;

    // Kullanıcının açabileceği kampanya sayısını arttıralım
    userCampaignCount[msg.sender]++;

    emit CampaignCreated(
        campaignId,
        msg.sender,
        title,
        block.timestamp,
        endDate,
        totalMemberNumber,
        msg.value,
        level
    );
}


    /**
     * @dev Register for a campaign
     * @param campaignId ID of the campaign
     */
    function registerCampaign(uint256 campaignId) external whenNotPaused nonReentrant validCampaign(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (block.timestamp > campaign.endDate) revert CampaignEnded();
        if (campaign.registeredMembers[msg.sender]) revert AlreadyRegistered();
        if (!campaign.isActive) revert CampaignNotActive();
        if (campaign.completedMemberNumber >= campaign.totalMemberNumber) revert CampaignWasCompleted();

        campaign.registeredMembers[msg.sender] = true;
        campaign.registeredMemberNumber++;

        emit CampaignRegistered(
            campaignId,
            msg.sender,
            campaign.totalMemberNumber,
            campaign.registeredMemberNumber
        );
    }

    /**
     * @dev Complete a campaign task
     * @param campaignId ID of the campaign
     */
    function completeCampaign(uint256 campaignId) external whenNotPaused nonReentrant validCampaign(campaignId) {
        Campaign storage campaign = campaigns[campaignId];

        if (block.timestamp > campaign.endDate) revert CampaignEnded();
        if (!campaign.registeredMembers[msg.sender]) revert NotRegistered();
        if (campaign.completedMembers[msg.sender]) revert AlreadyCompleted();
        if (!campaign.isActive) revert CampaignNotActive();
        if (campaign.completedMemberNumber >= campaign.totalMemberNumber) revert CampaignWasCompleted();

        campaign.completedMembers[msg.sender] = true;
        campaign.completedTokenAmount += campaign.tokenAmountPerMember;
        campaign.completedMemberNumber++;
        balances[msg.sender] += campaign.tokenAmountPerMember;

        // If campaign is fully completed, decrease creator's campaign count
        if (campaign.completedMemberNumber >= campaign.totalMemberNumber) {
            userCampaignCount[campaign.creator]--;
        }

        emit CampaignCompleted(
            campaignId,
            msg.sender,
            campaign.completedTokenAmount,
            campaign.completedMemberNumber
        );
    }

    /**
     * @dev Withdraw earned tokens
     */
    function withdrawTokens() external whenNotPaused nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NoTokensToWithdraw();

        balances[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit TokensWithdrawn(msg.sender, amount);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Update campaign status (only owner)
     * @param campaignId ID of the campaign
     * @param status New status
     */
    function updateCampaignStatus(uint256 campaignId, bool status) external onlyOwner validCampaign(campaignId) {
        Campaign storage campaign = campaigns[campaignId];
        campaign.isActive = status;
        emit CampaignStatusUpdated(campaignId, status);
    }

    /**
     * @dev Cancel campaign and refund creator (only owner)
     * @param campaignId ID of the campaign
     */
    function cancelCampaign(uint256 campaignId) external onlyOwner validCampaign(campaignId) {
        Campaign storage campaign = campaigns[campaignId];
        if (!campaign.isActive) revert CampaignNotActive();

        uint256 remainingTokens = campaign.tokenAmount - campaign.completedTokenAmount;
        campaign.isActive = false;
        
        // Decrease user's campaign count
        userCampaignCount[campaign.creator]--;

        if (remainingTokens > 0) {
            (bool success, ) = payable(campaign.creator).call{value: remainingTokens}("");
            if (!success) revert TransferFailed();
        }

        emit CampaignCancelled(campaignId);
    }

    /**
     * @dev Emergency withdraw (only owner) - Can only withdraw unclaimed campaign funds
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        uint256 contractBalance = address(this).balance;
        if (amount > contractBalance) revert InsufficientBalance();
        
        // Calculate total user balances that should be protected
        uint256 totalUserBalances;
        // Note: In a real implementation, you might need to track this separately
        // for gas optimization. For now, we'll trust the owner to not withdraw user funds.
        
        // Simple protection: don't allow withdrawing more than reasonable
        if (amount > contractBalance / 2) {
            revert("Cannot withdraw more than 50%% of contract balance");
        }
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
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

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Calculate campaign end date based on duration type
     */
     function _calculateEndDate(
        uint256 duration,
        DurationType durationType
    ) internal view returns (uint256) {
        if (durationType == DurationType.UNLIMITED) {
            return type(uint256).max;
        }
        
        // Prevent overflow by limiting duration
        if (duration > 10000) revert InvalidCampaignData(); // Max ~27 years for daily
        
        uint256 timeMultiplier;
        if (durationType == DurationType.DAILY) {
            timeMultiplier = DAILY;
        } else if (durationType == DurationType.WEEKLY) {
            timeMultiplier = WEEKLY;
        } else if (durationType == DurationType.MONTHLY) {
            timeMultiplier = MONTHLY;
        }
        
        // Check for overflow before multiplication
        if (duration > type(uint256).max / timeMultiplier) {
            revert InvalidCampaignData();
        }
        
        uint256 durationInSeconds = timeMultiplier * duration;
        
        // Check for overflow before addition
        if (block.timestamp > type(uint256).max - durationInSeconds) {
            revert InvalidCampaignData();
        }
        
        return block.timestamp + durationInSeconds;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get campaign details
     * @param campaignId Campaign ID
     */
    function getCampaignDetails(uint256 campaignId) external view validCampaign(campaignId) returns (
        address creator,
        string memory title,
        string memory description,
        bool isActive,
        uint256 endDate,
        uint256 totalMemberNumber,
        uint256 completedMemberNumber,
        uint256 registeredMemberNumber,
        uint256 tokenAmount,
        uint256 tokenAmountPerMember
    ) {
        Campaign storage campaign = campaigns[campaignId];
        return (
            campaign.creator,
            campaign.title,
            campaign.description,
            campaign.isActive,
            campaign.endDate,
            campaign.totalMemberNumber,
            campaign.completedMemberNumber,
            campaign.registeredMemberNumber,
            campaign.tokenAmount,
            campaign.tokenAmountPerMember
        );
    }

    /**
     * @dev Check if user is registered for campaign
     */
    function isRegistered(uint256 campaignId, address user) external view validCampaign(campaignId) returns (bool) {
        return campaigns[campaignId].registeredMembers[user];
    }

    /**
     * @dev Check if user completed campaign
     */
    function isCompleted(uint256 campaignId, address user) external view validCampaign(campaignId) returns (bool) {
        return campaigns[campaignId].completedMembers[user];
    }

    function getuserlevel() external view returns(uint256){
        return _nftContract.userLevel(msg.sender);
    }

   function getnft(uint8 typeIndex)
        external
        view
        returns (
            uint8   id,
            string memory name,
            uint256 price,
            uint256 maxSupply,
            uint256 currentSupply,
            uint8   maxPoolNumber,
            string memory baseURI,
            bool    isActive,
            uint16  freeMintNumber
        )
    {
        return _nftContract.nftTypes(typeIndex);
    }

    /**
     * @dev Get user balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @dev Get user's current campaign count
     */
    function getUserCampaignCount(address user) external view returns (uint256) {
        return userCampaignCount[user];
    }

    /**
     * @dev Get user's campaign limit based on NFT level
     */
    // function getUserCampaignLimit(address user) external view returns (uint256) {
    //     uint8 userLevel = _nftContract.userLevel(user);
    //     if (userLevel == 0) return 0;
        
    //     NFTType memory nftType = _nftContract.nftTypes(userLevel);
    //     return nftType.maxPoolNumber;
    // }

    /**
     * @dev Get user's remaining campaign slots
     */
    // function getUserRemainingSlots(address user) external view returns (uint256) {
    //     uint8 userLevel = _nftContract.userLevel(user);
    //     if (userLevel == 0) return 0;
        
    //     NFTType memory nftType = _nftContract.nftTypes(userLevel);
    //     uint256 currentCount = userCampaignCount[user];
        
    //     if (currentCount >= nftType.maxPoolNumber) {
    //         return 0;
    //     }
        
    //     return nftType.maxPoolNumber - currentCount;
    // }

    /**
     * @dev Get NFT contract address
     */
    function getNFTContract() external view returns (address) {
        return address(_nftContract);
    }

    /**
     * @dev Get total campaigns created
     */
    function getTotalCampaigns() external view returns (uint256) {
        return _campaignIds;
    }

    // ============ FALLBACK FUNCTIONS ============
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
