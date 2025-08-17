// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title ActivateEarth
 * @dev A contract for managing campaigns with token rewards
 * @notice This contract allows creation and management of campaigns where users can register, complete tasks and earn tokens
 */
contract ActivateEarthDapp is ReentrancyGuard, Pausable, Ownable, EIP712 {
    using ECDSA for bytes32;

    bytes32 private constant _BATCH_TYPEHASH =
        keccak256("Batch(address user,uint256[] campaignIds,uint256 nonce)");
    IERC20 public immutable token;
    uint256 private _campaignIds;
    address private _backendAddress;
    
    // Campaign structure
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

    // Batch process tracking
    mapping(bytes32 => bool) public processedBatches;

    // Events
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 startDate,
        uint256 endDate,
        uint256 totalMemberNumber,
        uint256 tokenAmount
    );
    event CampaignRegistered(uint256 indexed campaignId, address indexed member, uint256 totalMemberNumber, uint256 registeredMemberNumber);
    event CampaignCompleted(uint256 indexed campaignId, address indexed member, uint256 completedTokenAmount, uint256 completedMemberNumber);
    event BatchProcessed(address indexed user, uint256[] campaignIds, bytes32 batchId);
    event TokensWithdrawn(address indexed member, uint256 amount);
    event CampaignCancelled(uint256 indexed campaignId);
    event CampaignStatusUpdated(uint256 indexed campaignId, bool status);
    
    // Constants for duration calculations
    uint256 private constant DAILY = 1 days;
    uint256 private constant WEEKLY = 7 days;
    uint256 private constant MONTHLY = 30 days;
    
    // State variables
    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public nonces;
    /**
     * @dev Contract constructor
     * @param tokenAddress Address of the ERC20 token used for rewards
     */
    constructor(address tokenAddress, address backendAddress) Ownable(msg.sender) EIP712("ActivateEarthDapp", "1") {
        require(tokenAddress != address(0), "Invalid token address");
        token = IERC20(tokenAddress);
        _backendAddress = backendAddress;
    }
    
    /**
     * @dev Creates a new campaign
     * @param title Campaign title
     * @param description Campaign description
     * @param totalMemberNumber Total number of members allowed
     * @param durationType is the type of duration for the campaign
     */  
    function createCampaign(
        string memory title,
        string memory description,
        uint256 totalMemberNumber,
        uint256 duration,
        string memory durationType, // "DAILY", "WEEKLY", "MONTHLY", "UNLIMITED"
        uint256 tokenAmount
    ) external whenNotPaused nonReentrant {
        require(bytes(title).length > 0, "Title cannot be empty");
        require(bytes(description).length > 0, "Description cannot be empty");
        require(totalMemberNumber > 0, "Invalid member number");
        require(duration > 0, "Invalid duration");
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "First payment for creating campaign!");
        require(tokenAmount % totalMemberNumber == 0, "Token amount is not divisible by total member number");
        
        uint256 endDate;
        if (keccak256(bytes(durationType)) == keccak256(bytes("DAILY"))) {
            endDate = block.timestamp + DAILY * duration;
        } else if (keccak256(bytes(durationType)) == keccak256(bytes("WEEKLY"))) {
            endDate = block.timestamp + WEEKLY * duration;
        } else if (keccak256(bytes(durationType)) == keccak256(bytes("MONTHLY"))) {
            endDate = block.timestamp + MONTHLY * duration;
        } else if (keccak256(bytes(durationType)) == keccak256(bytes("UNLIMITED"))) {
            endDate = type(uint256).max; // Maximum possible value
        } else {
            require(false, "Invalid duration type");
        }

        _campaignIds++;
        uint256 campaignId = _campaignIds;
        Campaign storage newCampaign = campaigns[campaignId];
        
        newCampaign.id = campaignId;
        newCampaign.creator = msg.sender;
        newCampaign.title = title;
        newCampaign.description = description;
        newCampaign.isActive = true;
        newCampaign.endDate = endDate;
        newCampaign.tokenAmount = tokenAmount;
        newCampaign.tokenAmountPerMember = tokenAmount / totalMemberNumber;
        newCampaign.totalMemberNumber = totalMemberNumber;
        
        emit CampaignCreated(
            campaignId,
            msg.sender,
            title,
            block.timestamp,
            endDate,
            totalMemberNumber,
            tokenAmount
        );
    }


    function _verifyBatch(
    address user,
    uint256[] calldata campaignIds,
    uint256 nonce,
    bytes calldata signature
) internal view returns (address) {
    bytes32 structHash = keccak256(
        abi.encode(
            _BATCH_TYPEHASH,
            user,
            keccak256(abi.encodePacked(campaignIds)),
            nonce
        )
    );
    // domainSeparator + structHash birleşimi
    bytes32 digest = _hashTypedDataV4(structHash);
    return ECDSA.recover(digest, signature);
}

    /**
     * @dev Batch process multiple campaign completions for a user
     * @param user Address of the user
     * @param campaignIds Array of campaign IDs
     * @param signature Backend signature to verify the batch

     */
   function batchCompleteCampaigns(
    address user,
    uint256[] calldata campaignIds,
    uint256 nonce,
    bytes calldata signature
) external whenNotPaused nonReentrant {
    // 1) Nonce kontrolü (replay engelleme)
    require(nonce == nonces[user], "Invalid nonce");

    // 2) Batch ID’yi oluştur ve işlenmiş mi kontrol et
    bytes32 batchId = keccak256(abi.encodePacked(user, campaignIds, nonce));
    require(!processedBatches[batchId], "Batch already processed");

    // 3) EIP-712 ile imzayı doğrula
    address signer = _verifyBatch(user, campaignIds, nonce, signature);
    require(signer == _backendAddress, "Invalid backend signature");

    // 4) Nonce ve processedBatches’i güncelle
    nonces[user] += 1;
    processedBatches[batchId] = true;

    // 5) Orijinal logiği aynen uygula
    uint256 totalReward = 0;
    for (uint256 i = 0; i < campaignIds.length; i++) {
        uint256 campaignId = campaignIds[i];
        Campaign storage campaign = campaigns[campaignId];

        if (
            block.timestamp <= campaign.endDate &&
            campaign.isActive &&
            !campaign.completedMembers[user] &&
            campaign.completedMemberNumber < campaign.totalMemberNumber
        ) {
            if (!campaign.registeredMembers[user]) {
                campaign.registeredMembers[user] = true;
                campaign.registeredMemberNumber++;
                emit CampaignRegistered(
                    campaignId,
                    user,
                    campaign.totalMemberNumber,
                    campaign.registeredMemberNumber
                );
            }

            campaign.completedMembers[user] = true;
            campaign.completedTokenAmount += campaign.tokenAmountPerMember;
            campaign.completedMemberNumber++;
            totalReward += campaign.tokenAmountPerMember;

            emit CampaignCompleted(
                campaignId,
                user,
                campaign.completedTokenAmount,
                campaign.completedMemberNumber
            );
        }
    }

    if (totalReward > 0) {
        balances[user] += totalReward;
    }

    emit BatchProcessed(user, campaignIds, batchId);
}
    // Legacy functions kept for backwards compatibility
    /**
     * @dev Allows users to register for a campaign
     * @param campaignId ID of the campaign
     */
    function registerCampaign(uint256 campaignId) external whenNotPaused nonReentrant {
        Campaign storage campaign = campaigns[campaignId];
        
        require(block.timestamp <= campaign.endDate, "Campaign ended");
        require(!campaign.registeredMembers[msg.sender], "Already registered");
        require(campaign.isActive, "Campaign not active");
        require(campaign.completedMemberNumber < campaign.totalMemberNumber, "Campaign completed");

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
     * @dev Marks a campaign as completed for a user
     * @param campaignId ID of the campaign
     */
    function completeCampaignWithSignature(uint256 campaignId, bytes calldata signature, bytes32 messageHash) external whenNotPaused nonReentrant {
        Campaign storage campaign = campaigns[campaignId];
        
        require(block.timestamp <= campaign.endDate, "Campaign ended");
        require(campaign.registeredMembers[msg.sender], "Not registered");
        require(!campaign.completedMembers[msg.sender], "Already completed");
        require(campaign.isActive, "Campaign not active");
        require(campaign.completedMemberNumber < campaign.totalMemberNumber, "Campaign completed");
        
        bytes32 messageHashSignedEth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",messageHash));
        address signer = getSigner(messageHashSignedEth, signature);

        require(_backendAddress == signer,"Backend Address is Invalid");
        
        campaign.completedMembers[msg.sender] = true;
        campaign.completedTokenAmount += campaign.tokenAmountPerMember;
        campaign.completedMemberNumber++;
        balances[msg.sender] += campaign.tokenAmountPerMember;
        
        emit CampaignCompleted(
            campaignId,
            msg.sender,
            campaign.completedTokenAmount,
            campaign.completedMemberNumber
        );
    }

    function getSigner(bytes32 ethSignedMessage, bytes memory signature) internal pure returns(address){
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedMessage, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns(bytes32 r, bytes32 s, uint8 v){
        require(sig.length == 65, "Invalid Signature");

        assembly {
            r := mload(add(sig,32))
            s := mload(add(sig,64))
            v := byte(0, mload(add(sig,96)))
        }
    }

    /**
     * @dev Sets the backend address
     * @param newBackend New backend address
     */
    function setBackendAddress(address newBackend) external onlyOwner {
    require(newBackend != address(0), "Invalid address");
    _backendAddress = newBackend;
}


    /**
     * @dev Allows users to withdraw their earned tokens
     */
    function withdrawTokens() external whenNotPaused nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No tokens to withdraw");
        
        balances[msg.sender] = 0;
        require(token.transfer(msg.sender, amount), "Token transfer failed");
        
        emit TokensWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Updates campaign status
     * @param campaignId ID of the campaign
     * @param status New status
     */
    function updateCampaignStatus(uint256 campaignId, bool status) external onlyOwner {
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.isActive != status, "Status already set");
        campaign.isActive = status;
        
        emit CampaignStatusUpdated(campaignId, status);
    }
    
    /**
     * @dev Cancels a campaign and returns tokens to creator
     * @param campaignId ID of the campaign
     */
    function cancelCampaign(uint256 campaignId) external onlyOwner {
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.isActive, "Campaign already cancelled");
        
        uint256 remainingTokens = campaign.tokenAmount - campaign.completedTokenAmount;
        if (remainingTokens > 0) {
            require(token.transfer(campaign.creator, remainingTokens), "Token return failed");
        }
        
        campaign.isActive = false;
        emit CampaignCancelled(campaignId);
    }
    
    /**
     * @dev Withdraws any remaining tokens in case of emergency
     * @param amount Amount of tokens to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= token.balanceOf(address(this)), "Insufficient balance");
        require(token.transfer(owner(), amount), "Transfer failed");
    }
    
    /**
     * @dev Returns campaign details
     * @param campaignId ID of the campaign
     */
    function getCampaignDetails(uint256 campaignId) external view returns (
        address creator,
        string memory title,
        string memory description,
        bool isActive,
        uint256 endDate,
        uint256 totalMemberNumber,
        uint256 completedMemberNumber
    ) {
        Campaign storage campaign = campaigns[campaignId];
        return (
            campaign.creator,
            campaign.title,
            campaign.description,
            campaign.isActive,
            campaign.endDate,
            campaign.totalMemberNumber,
            campaign.completedMemberNumber
        );
    }
    
    /**
     * @dev Checks if a user is registered for a campaign
     */
    function isRegistered(uint256 campaignId, address user) external view returns (bool) {
        return campaigns[campaignId].registeredMembers[user];
    }
    
    /**
     * @dev Checks if a user has completed a campaign
     */
    function isCompleted(uint256 campaignId, address user) external view returns (bool) {
        return campaigns[campaignId].completedMembers[user];
    }
    
    /**
     * @dev Returns user balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}