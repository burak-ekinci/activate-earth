// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title ActivateEarth Native DApp
 * @dev Campaign-based reward system using native chain coin
 */
contract ActivateEarthDapp is ReentrancyGuard,Ownable, Pausable, EIP712 {
    using ECDSA for bytes32;
    using Address for address payable;

    bytes32 private constant _BATCH_TYPEHASH =
        keccak256("Batch(address user,uint256[] campaignIds,uint256 nonce)");

    uint256 private _campaignIds;
    address private _backendAddress;

    struct Campaign {
        uint256 id;
        address creator;
        string title;
        string description;
        bool isActive;
        uint256 endDate;
        uint256 totalMemberNumber;
        uint256 totalAmount;
        uint256 amountPerMember;
        uint256 distributedAmount;
        uint256 completedCount;
        uint256 registeredCount;
        mapping(address => bool) registered;
        mapping(address => bool) completed;
    }

    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public processedBatches;

    // Duration constants
    uint256 private constant DAILY = 1 days;
    uint256 private constant WEEKLY = 7 days;
    uint256 private constant MONTHLY = 30 days;
    uint256 constant MAX_DURATION = 365; // Maksimum 1 yıl
    uint256 constant MAX_MEMBERS = 10000; // Maksimum üye sayısı
    uint256 constant MIN_AMOUNT_PER_MEMBER = 0.0001 ether; // Minimum miktar

    uint256 public maxDailyWithdraw = 10 ether;
    mapping(uint256 => uint256) public dailyWithdrawn; // day => amount

    modifier circuitBreaker(uint256 amount) {
        uint256 today = block.timestamp / 1 days;
        require(
            dailyWithdrawn[today] + amount <= maxDailyWithdraw,
            "Daily limit exceeded"
        );
        dailyWithdrawn[today] += amount;
        _;
    }

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 startDate,
        uint256 endDate,
        uint256 totalMemberNumber,
        uint256 totalAmount
    );
    event CampaignRegistered(
        uint256 indexed campaignId,
        address indexed member,
        uint256 totalMemberNumber,
        uint256 registeredCount
    );
    event CampaignCompleted(
        uint256 indexed campaignId,
        address indexed member,
        uint256 distributedAmount,
        uint256 completedCount
    );
    event BatchProcessed(address indexed user, uint256[] campaignIds, bytes32 batchId);
    event Withdrawn(address indexed member, uint256 amount);
    event CampaignCancelled(uint256 indexed campaignId);
    event CampaignStatusUpdated(uint256 indexed campaignId, bool status);
    event EmergencyWithdraw(address indexed owner, uint256 amount);
    event BackendChanged(address indexed oldBackend, address indexed newBackend);

    constructor(address backendAddress)
        Ownable(msg.sender)
        EIP712("ActivateEarthDapp", "1")
    {
        require(backendAddress != address(0), "Invalid backend");
        _backendAddress = backendAddress;
    }

    enum DurationType {
        DAILY,
        WEEKLY,
        MONTHLY,
        UNLIMITED
    }

    /**
     * @dev Create a campaign by sending native coin to contract
     */
  function createCampaign(
        string      memory title,
        string      memory description,
        uint256             totalMemberNumber,
        uint256             duration,
        DurationType        durationType
    )
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(bytes(title).length > 0, "Empty title");
        require(bytes(description).length > 0, "Empty desc");
        require(duration > 0 && duration <= MAX_DURATION, "Invalid duration");
        require(totalMemberNumber > 0 && totalMemberNumber <= MAX_MEMBERS, "Invalid member count");
        require(msg.value > 0, "No funds sent");

        uint256 perMember = msg.value / totalMemberNumber;
        require(perMember >= MIN_AMOUNT_PER_MEMBER, "Per member too small");
        require(msg.value % totalMemberNumber == 0, "Amount not divisible");

        uint256 endDate;
        if (durationType == DurationType.DAILY) {
            endDate = block.timestamp + DAILY * duration;
        } else if (durationType == DurationType.WEEKLY) {
            endDate = block.timestamp + WEEKLY * duration;
        } else if (durationType == DurationType.MONTHLY) {
            endDate = block.timestamp + MONTHLY * duration;
        } else {
            endDate = type(uint256).max; // UNLIMITED
        }

        _campaignIds++;
        Campaign storage c = campaigns[_campaignIds];
        c.id                = _campaignIds;
        c.creator           = msg.sender;
        c.title             = title;
        c.description       = description;
        c.isActive          = true;
        c.endDate           = endDate;
        c.totalMemberNumber = totalMemberNumber;
        c.totalAmount       = msg.value;
        c.amountPerMember   = perMember;

        emit CampaignCreated(
            _campaignIds,
            msg.sender,
            title,
            block.timestamp,
            endDate,
            totalMemberNumber,
            msg.value
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
                nonce,
                block.chainid  // Chain ID ekle
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }

    /**
     * @dev Batch completion via backend-signed proof
     */
  function batchCompleteCampaigns(
    address user,
    uint256[] calldata campaignIds,
    uint256 nonce,
    bytes calldata signature
) external whenNotPaused nonReentrant {
    // 1) Replay koruması
    require(nonce == nonces[user], "Invalid nonce");
    bytes32 batchId = keccak256(abi.encodePacked(user, campaignIds, nonce));
    require(!processedBatches[batchId], "Batch processed");

    // 2) İmzayı doğrula (TYPEHASH ile eşleşmeli; block.chainid burada olmamalı)
    address signer = _verifyBatch(user, campaignIds, nonce, signature);
    require(signer == _backendAddress, "Bad signature");

    // 3) İşlemi kayıt et
    nonces[user]++;
    processedBatches[batchId] = true;

    // 4) Ödülleri hesapla ve ata
    uint256 totalReward;
    for (uint256 i = 0; i < campaignIds.length; ) {
        Campaign storage c = campaigns[campaignIds[i]];
        if (
            block.timestamp <= c.endDate &&
            c.isActive &&
            !c.completed[user] &&
            c.completedCount < c.totalMemberNumber
        ) {
            // (a) Kayıt yoksa kaydet
            if (!c.registered[user]) {
                c.registered[user] = true;
                c.registeredCount++;
                emit CampaignRegistered(
                    c.id, user, c.totalMemberNumber, c.registeredCount
                );
            }
            // (b) Tamamla ve ödül ekle
            c.completed[user] = true;
            c.distributedAmount += c.amountPerMember;
            c.completedCount++;
            totalReward += c.amountPerMember;
            emit CampaignCompleted(
                c.id, user, c.distributedAmount, c.completedCount
            );
        }
        unchecked { i++; }
    }

    // 5) Bakiye güncelle
    if (totalReward > 0) balances[user] += totalReward;
    emit BatchProcessed(user, campaignIds, batchId);
}

/**
 * @dev Allows a user to register for a campaign
 * @param campaignId ID of the campaign to register for
 */
function registerCampaign(uint256 campaignId)
    external
    whenNotPaused
    nonReentrant
{
    // Validate campaign exists
    require(campaignId > 0 && campaignId <= _campaignIds, "Invalid campaignId");

    Campaign storage campaign = campaigns[campaignId];

    // Must be active and not yet ended
    require(campaign.isActive, "Campaign not active");
    require(block.timestamp <= campaign.endDate, "Campaign ended");

    // Prevent double‐registration
    require(!campaign.registered[msg.sender], "Already registered");

    // Prevent registrations once capacity reached
    require(
        campaign.registeredCount < campaign.totalMemberNumber,
        "Campaign full"
    );

    // Mark registration
    campaign.registered[msg.sender] = true;
    campaign.registeredCount++;

    emit CampaignRegistered(
        campaignId,
        msg.sender,
        campaign.totalMemberNumber,
        campaign.registeredCount
    );
}


    /**
     * @dev Withdraw accumulated native coin rewards
     */
    function withdraw() external whenNotPaused nonReentrant circuitBreaker(balances[msg.sender]) {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        balances[msg.sender] = 0;
        payable(msg.sender).sendValue(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Pause/unpause and owner-only controls
     */
    function updateCampaignStatus(uint256 campaignId, bool status) external onlyOwner {
        campaigns[campaignId].isActive = status;
        emit CampaignStatusUpdated(campaignId, status);
    }

    function cancelCampaign(uint256 campaignId) external {
        Campaign storage c = campaigns[campaignId];
        require(c.isActive, "Not active");
        require(
            msg.sender == owner() || msg.sender == c.creator,
            "Not authorized"
        );
        
        uint256 remaining = c.totalAmount - c.distributedAmount;
        if (remaining > 0) payable(c.creator).sendValue(remaining);
        c.isActive = false;
        emit CampaignCancelled(campaignId);
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner()).sendValue(amount);
        emit EmergencyWithdraw(owner(), amount);
    }

    /**
     * @dev View helpers
     */
    function getCampaignDetails(uint256 campaignId)
        external
        view
        returns (
            address creator,
            string memory title,
            string memory description,
            bool isActive,
            uint256 endDate,
            uint256 totalMemberNumber,
            uint256 completedCount
        ) {
        Campaign storage c = campaigns[campaignId];
        return (
            c.creator,
            c.title,
            c.description,
            c.isActive,
            c.endDate,
            c.totalMemberNumber,
            c.completedCount
        );
    }

    function isRegistered(uint256 campaignId, address user) external view returns (bool) {
        return campaigns[campaignId].registered[user];
    }

    function isCompleted(uint256 campaignId, address user) external view returns (bool) {
        return campaigns[campaignId].completed[user];
    }
    /**
     * @dev Set backend
     */
    function setBackendAddress(address newBackend) external onlyOwner {
        require(newBackend != address(0), "Invalid backend");
        address oldBackend = _backendAddress;
        _backendAddress = newBackend;
        
        // Eski backend'in nonce'larını temizle (isteğe bağlı)
        emit BackendChanged(oldBackend, newBackend);
    }

    /**
    *@dev Disable 
    */
    function renounceOwnership() public view override onlyOwner {
        revert("Disabled!");
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


    /**
     * @dev Fallback to accept native coin
     */
    receive() external payable {}
    fallback() external payable {}
}
