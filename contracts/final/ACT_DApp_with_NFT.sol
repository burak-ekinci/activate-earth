// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ActivateEarth NFT Interface
 * @dev Interface for interacting with ActivateEarthNFT contract
 */
interface IActivateEarthNFT {
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

    function getUserOwnedNFT(address user, uint8 _nftTypeIndex) external view returns (bool);
    function getNftTypeCounter() external view returns (uint8);
    function userLevel(address) external view returns (uint8);

    /// CLEAN API: Struct döndürür (auto-getter kullanmayın)
    function getNftType(uint8 idx) external view returns (NFTType memory);
}

/**
 * @title Chainlink PriceFeed Interface
 * @dev Interface for interacting with Chainlink PriceFeed contract
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80);
}


/**
 * @title ActivateEarthDapp
 * @dev Campaign management system with NFT level restrictions
 */
contract ActivateEarthDapp is ReentrancyGuard, Pausable, Ownable {

    // ============ STATE VARIABLES ============
    IActivateEarthNFT private _nftContract;
    AggregatorV3Interface private _priceFeed;
    uint256 private _campaignIds;
    uint256 public accruedFees;
    uint256 public maxPriceStaleness = 24 hours;
    uint16 public platformFeeBps = 500; 

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

    // (DİKKAT) DApp içinde NFTType struct YOK — yalnızca interface tarafındaki kullanılacak

    // ============ MAPPINGS ============
    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public userCampaignCount;

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
    event PlatformFeeUpdated(uint16 newBps);


    // ============ CONSTANTS ============
    uint256 private constant DAILY = 1 days;

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
    error RegistrationFull();
    error NotCreator();
    error TooEarly();
    //chainlink
    error PriceFeedNotSet();
    error InvalidOracleAnswer();
    error StalePrice();
    error BelowMinPerMember(uint256 minWei, uint256 givenWei);

    // ============ MODIFIERS ============
    modifier validCampaign(uint256 campaignId) {
        if (campaignId == 0 || campaignId > _campaignIds) revert CampaignNotFound();
        if (campaigns[campaignId].creator == address(0)) revert CampaignNotFound();
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(address nftContractAddress) Ownable(msg.sender) {
        if (nftContractAddress == address(0)) revert InvalidNFTContract();
        _nftContract = IActivateEarthNFT(nftContractAddress);
    }

    // ============ MAIN FUNCTIONS ============

    /**
     * @dev Creates a new campaign with NFT level restrictions
     */
function createCampaign(
    string memory title,
    string memory description,
    uint256 totalMemberNumber,
    uint256 duration
) external payable whenNotPaused nonReentrant {
    if (bytes(title).length == 0)             revert InvalidCampaignData();
    if (bytes(description).length == 0)       revert InvalidCampaignData();
    if (totalMemberNumber == 0)               revert InvalidCampaignData();
    if (duration == 0)                        revert InvalidCampaignData();
    if (msg.value == 0)                       revert InvalidCampaignData();

    // ---- NFT level ----
    uint8 level;
    {
        try _nftContract.userLevel(msg.sender) returns (uint8 _level) {
            level = _level;
        } catch {
            revert NFTContractCallFailed();
        }
    }
    if (level == 0) revert UserHasNoNFT();

    {
        try _nftContract.getNftType(level) returns (IActivateEarthNFT.NFTType memory t) {
            if (!t.isActive) revert NFTTypeNotActive();
            if (userCampaignCount[msg.sender] >= t.maxPoolNumber) revert CampaignLimitReached();
        } catch {
            revert NFTContractCallFailed();
        }
    }

    uint256 endDate = _calculateEndDate(duration);

    _campaignIds++;
    uint256 campaignId = _campaignIds;
    Campaign storage c = campaigns[campaignId];

    // Önce storage’a yazalım (stack basıncını azaltır)
    c.id               = campaignId;
    c.creator          = msg.sender;
    c.title            = title;
    c.description      = description;
    c.isActive         = true;
    c.endDate          = endDate;
    c.totalMemberNumber= totalMemberNumber;

    // ---- Fee ve net hesap (kısa kapsam) ----
    {
        uint256 fee = (msg.value * platformFeeBps) / 10_000; // BPS_DENOMINATOR kullanıyorsan ona göre değiştir
        uint256 net = msg.value - fee;

        if (net % totalMemberNumber != 0) revert InvalidCampaignData();

        // (opsiyonel) min $0.01 kontrolü net üzerinden yapıyorsan burada:
        // uint256 perMember = net / totalMemberNumber;
        // uint256 minWei = _minPerMemberWei();
        // if (perMember < minWei) revert BelowMinPerMember(minWei, perMember);

        accruedFees += fee;

        c.tokenAmount          = net;
        c.tokenAmountPerMember = net / totalMemberNumber;
    }

    userCampaignCount[msg.sender]++;

    // Event'te local değişkenler yerine storage alanlarını kullan
    emit CampaignCreated(
        campaignId,
        msg.sender,
        c.title,
        block.timestamp,
        c.endDate,
        c.totalMemberNumber,
        c.tokenAmount,
        level
    );
}


    /**
     * @dev Register for a campaign
     */
    function registerCampaign(uint256 campaignId)
        external
        whenNotPaused
        nonReentrant
        validCampaign(campaignId)
    {
        Campaign storage campaign = campaigns[campaignId];

        if (block.timestamp > campaign.endDate) revert CampaignEnded();
        if (!campaign.isActive) revert CampaignNotActive();

        // KAPASİTE KONTROLÜ — over-registration engeli
        if (campaign.registeredMemberNumber >= campaign.totalMemberNumber) revert RegistrationFull();

        if (campaign.registeredMembers[msg.sender]) revert AlreadyRegistered();
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
     */
    function completeCampaign(uint256 campaignId)
        external
        whenNotPaused
        nonReentrant
        validCampaign(campaignId)
    {
        Campaign storage campaign = campaigns[campaignId];

        if (block.timestamp > campaign.endDate) revert CampaignEnded();
        if (!campaign.isActive) revert CampaignNotActive();
        if (!campaign.registeredMembers[msg.sender]) revert NotRegistered();
        if (campaign.completedMembers[msg.sender]) revert AlreadyCompleted();
        if (campaign.completedMemberNumber >= campaign.totalMemberNumber) revert CampaignWasCompleted();

        campaign.completedMembers[msg.sender] = true;
        campaign.completedTokenAmount += campaign.tokenAmountPerMember;
        campaign.completedMemberNumber++;
        balances[msg.sender] += campaign.tokenAmountPerMember;

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

    // ============ POST-END FINALIZATION ============

    /**
     * @dev Creator can finalize after end date to reclaim remaining funds
     */
    function finalizeAfterEnd(uint256 campaignId)
        external
        nonReentrant
        validCampaign(campaignId)
    {
        Campaign storage campaign = campaigns[campaignId];
        if (msg.sender != campaign.creator) revert NotCreator();
        if (block.timestamp <= campaign.endDate) revert TooEarly();
        if (!campaign.isActive) revert CampaignNotActive();

        uint256 remaining = campaign.tokenAmount - campaign.completedTokenAmount;
        campaign.isActive = false;
        userCampaignCount[campaign.creator]--;

        if (remaining > 0) {
            (bool ok, ) = payable(campaign.creator).call{value: remaining}("");
            if (!ok) revert TransferFailed();
        }

        emit CampaignCancelled(campaignId); // istersen ayrı "Finalized" eventi ekleyebilirsin
    }

    // ============ ADMIN FUNCTIONS ============
// campaign ownerı kendi statusunu değişebilmeli
    function updateCampaignStatus(uint256 campaignId, bool status)
        external
        onlyOwner
        nonReentrant
        validCampaign(campaignId)
    {
        Campaign storage campaign = campaigns[campaignId];
        campaign.isActive = status;
        emit CampaignStatusUpdated(campaignId, status);
    }

    function cancelCampaign(uint256 campaignId)
        external
        onlyOwner
        nonReentrant
        validCampaign(campaignId)
    {
        Campaign storage campaign = campaigns[campaignId];
        if (!campaign.isActive) revert CampaignNotActive();

        uint256 remainingTokens = campaign.tokenAmount - campaign.completedTokenAmount;
        campaign.isActive = false;
        userCampaignCount[campaign.creator]--;

        if (remainingTokens > 0) {
            (bool success, ) = payable(campaign.creator).call{value: remainingTokens}("");
            if (!success) revert TransferFailed();
        }

        emit CampaignCancelled(campaignId);
    }

    /**
     * @dev Emergency withdraw (owner)
     * UYARI: Ürün politikanıza göre kısıtlayın ya da kaldırın.
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner nonReentrant {
        uint256 contractBalance = address(this).balance;
        if (amount > contractBalance) revert InsufficientBalance();

        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function pause() external onlyOwner nonReentrant { _pause(); }
    function unpause() external onlyOwner nonReentrant { _unpause(); }

    // ============ INTERNAL FUNCTIONS ============

    function _calculateEndDate(uint256 days_) internal view returns (uint256) {
        if (days_ == 0 || days_ > 10_000) revert InvalidCampaignData();
        return block.timestamp + days_ * 1 days; // yeterli
    }

    function _minPerMemberWei() internal view returns (uint256) {
    if (address(_priceFeed) == address(0)) revert PriceFeedNotSet();

    (, int256 answer,, uint256 updatedAt,) = _priceFeed.latestRoundData();
    if (answer <= 0) revert InvalidOracleAnswer();
    if (updatedAt + maxPriceStaleness < block.timestamp) revert StalePrice();

    uint8 p = _tryDecimals(_priceFeed);            // örn. 8
    uint256 priceScaled = uint256(answer);         // USD fiyatı * 10^p
    uint256 scale = 10 ** uint256(p);

    // minWei for $0.01 = (1 ETH * 10^p) / (priceScaled * 100)
    // → integer güvenli (1e18 * 1e8 / (price*100))
    return (1e18 * scale) / (priceScaled * 100);
    }

    function _tryDecimals(AggregatorV3Interface feed) private view returns (uint8) {
        // çoğu feed decimals() destekler; çağrı ucuzdur ve revert etmez
        try feed.decimals() returns (uint8 d) { return d; } catch { return 8; }
    }

    // ============ VIEW FUNCTIONS ============

    function getCampaignDetails(uint256 campaignId)
        external
        view
        validCampaign(campaignId)
        returns (
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
        )
    {
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

    function isRegistered(uint256 campaignId, address user)
        external
        view
        validCampaign(campaignId)
        returns (bool)
    {
        return campaigns[campaignId].registeredMembers[user];
    }

    function isCompleted(uint256 campaignId, address user)
        external
        view
        validCampaign(campaignId)
        returns (bool)
    {
        return campaigns[campaignId].completedMembers[user];
    }

    function getuserlevel() external view returns (uint256) {
        return _nftContract.userLevel(msg.sender);
    }

    /// Eski arayüzü koruyarak struct'tan parçalayarak döndürürüz
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
        IActivateEarthNFT.NFTType memory t = _nftContract.getNftType(typeIndex);
        return (t.id, t.name, t.price, t.maxSupply, t.currentSupply, t.maxPoolNumber, t.baseURI, t.isActive, t.freeMintNumber);
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function getUserCampaignCount(address user) external view returns (uint256) {
        return userCampaignCount[user];
    }

    function getUserCampaignLimit(address user) external view returns (uint256) {
        uint8 userLevel = _nftContract.userLevel(user);
        if (userLevel == 0) return 0;

        IActivateEarthNFT.NFTType memory nftType = _nftContract.getNftType(userLevel);
        return nftType.maxPoolNumber;
    }

    function getUserRemainingSlots(address user) external view returns (uint256) {
        uint8 userLevel = _nftContract.userLevel(user);
        if (userLevel == 0) return 0;

        IActivateEarthNFT.NFTType memory nftType = _nftContract.getNftType(userLevel);
        uint256 currentCount = userCampaignCount[user];
        if (currentCount >= nftType.maxPoolNumber) return 0;

        return nftType.maxPoolNumber - currentCount;
    }

    function getNFTContract() external view returns (address) {
        return address(_nftContract);
    }

    function getTotalCampaigns() external view returns (uint256) {
        return _campaignIds;
    }

    // ============ SETTER FUNCTIONS ============
    
    function setPlatformFeeBps(uint16 newBps) external onlyOwner nonReentrant {
    platformFeeBps = newBps;
    emit PlatformFeeUpdated(newBps);
    }

    function setPriceFeed(address feed) external onlyOwner {
    require(feed != address(0), "zero feed");
    _priceFeed = AggregatorV3Interface(feed);
    }

    function setMaxPriceStaleness(uint256 seconds_) external onlyOwner {
        require(seconds_ >= 60 && seconds_ <= 7 days, "bad staleness");
        maxPriceStaleness = seconds_;
    }

    // ============ FALLBACK ============
    receive() external payable {}
    fallback() external payable {}
}
