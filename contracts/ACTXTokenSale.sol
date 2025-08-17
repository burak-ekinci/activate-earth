// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// interface IVesting {
//     function addBeneficiary(
//         address _beneficiary,
//         uint256 _totalAmount,
//         uint256 tgeReleasedPercentage,
//         uint256 _cliff,
//         uint256 _duration
//     ) external;
// }

// /**
//  * @title ACTXTokenSale
//  * @dev Manages token sale rounds with vesting schedules
//  * Includes VC, Private, and Public rounds with different parameters
//  */
// contract ACTXTokenSale is Ownable, ReentrancyGuard, Pausable {
//     IERC20 public _token;
//     IVesting public _vestingContract;
//     uint8 private constant TOKEN_DECIMALS = 18;

//     // Structure to store round details and investor information
//     struct SaleRound {
//         uint256 rate;                 // Token price rate
//         uint256 totalTokenLimit;      // Maximum tokens for this round
//         uint256 saleLimitPerAddress;  // Maximum tokens per address
//         bool isActive;                // Round status
//         uint256 totalTokenSold;       // Total tokens sold in this round
//         uint256 investorNumber;       // Number of whitelisted investors
//         uint256 cliff;                // Vesting cliff period
//         uint256 duration;             // Vesting duration
//         uint256 tgePercentage;        // Token Generation Event percentage
//         mapping(address => bool) investors;      // Whitelisted investors
//         mapping(address => uint256) saleAmount;  // Amount bought per investor
//     }
    
//     SaleRound public _vcRound;
//     SaleRound public _privateRound;
//     SaleRound public _publicRound;

//     // Events for important state changes
//     event TokensPurchased(address indexed buyer, uint256 amount, string saleType);
//     event RateUpdated(string saleType, uint256 newRate);
//     event InvestorAdded(string roundType, address investor);
//     event InvestorRemoved(string roundType, address investor);
//     event RoundStatusChanged(string roundType, bool isActive);
//     event EmergencyWithdraw(address indexed owner, uint256 amount);

//     /**
//      * @dev Constructor to initialize the token sale contract
//      * @param token The ERC20 token address being sold
//      * @param vestingContract The vesting contract address
//      */
//     constructor(
//         address token,
//         address vestingContract
//     ) Ownable(msg.sender) {
//         require(token != address(0), "Token address cannot be zero");
//         require(vestingContract != address(0), "Vesting contract address cannot be zero");

//         _token = IERC20(token);
//         _vestingContract = IVesting(vestingContract);
//     }

//     /**
//      * @dev Sets up the VC round parameters
//      * @param rate Token price rate
//      * @param totalTokenLimit Maximum tokens for VC round
//      * @param saleLimitPerAddress Maximum tokens per address
//      * @param isActive Round status
//      * @param cliff Vesting cliff period
//      * @param duration Vesting duration
//      * @param tgePercentage Initial token release percentage
//      */
//     function setVCRound(
//         uint256 rate, 
//         uint256 totalTokenLimit, 
//         uint256 saleLimitPerAddress, 
//         bool isActive, 
//         uint256 cliff, 
//         uint256 duration,
//         uint256 tgePercentage
//     ) external onlyOwner {
//         require(rate > 0, "Rate must be greater than 0");
//         require(totalTokenLimit > 0, "Total token limit must be greater than 0");
//         require(tgePercentage <= 100, "TGE percentage cannot exceed 100");
        
//         _vcRound.rate = rate;
//         _vcRound.totalTokenLimit = totalTokenLimit;
//         _vcRound.saleLimitPerAddress = saleLimitPerAddress;
//         _vcRound.isActive = isActive;
//         _vcRound.cliff = cliff;
//         _vcRound.duration = duration;
//         _vcRound.tgePercentage = tgePercentage;
        
//         emit RateUpdated("VC", rate);
//     }

//     /**
//      * @dev Sets up the Private round parameters
//      */
//     function setPrivateRound(
//         uint256 rate, 
//         uint256 totalTokenLimit, 
//         uint256 saleLimitPerAddress, 
//         bool isActive, 
//         uint256 cliff, 
//         uint256 duration,
//         uint256 tgePercentage
//     ) external onlyOwner {
//         require(rate > 0, "Rate must be greater than 0");
//         require(totalTokenLimit > 0, "Total token limit must be greater than 0");
//         require(tgePercentage <= 100, "TGE percentage cannot exceed 100");
        
//         _privateRound.rate = rate;
//         _privateRound.totalTokenLimit = totalTokenLimit;
//         _privateRound.saleLimitPerAddress = saleLimitPerAddress;
//         _privateRound.isActive = isActive;
//         _privateRound.cliff = cliff;
//         _privateRound.duration = duration;
//         _privateRound.tgePercentage = tgePercentage;
        
//         emit RateUpdated("Private", rate);
//     }

//     /**
//      * @dev Sets up the Public round parameters
//      */
//     function setPublicRound(
//         uint256 rate, 
//         uint256 totalTokenLimit, 
//         uint256 saleLimitPerAddress, 
//         bool isActive, 
//         uint256 cliff, 
//         uint256 duration,
//         uint256 tgePercentage
//     ) external onlyOwner {
//         require(rate > 0, "Rate must be greater than 0");
//         require(totalTokenLimit > 0, "Total token limit must be greater than 0");
//         require(tgePercentage <= 100, "TGE percentage cannot exceed 100");
        
//         _publicRound.rate = rate;
//         _publicRound.totalTokenLimit = totalTokenLimit;
//         _publicRound.saleLimitPerAddress = saleLimitPerAddress;
//         _publicRound.isActive = isActive;
//         _publicRound.cliff = cliff;
//         _publicRound.duration = duration;
//         _publicRound.tgePercentage = tgePercentage;
        
//         emit RateUpdated("Public", rate);
//     }

//     /**
//      * @dev Adds an investor to the VC round whitelist
//      * @param investor Address to be whitelisted
//      */
//     function addVCInvestor(address investor) external onlyOwner {
//         require(investor != address(0), "Invalid investor address");
//         require(!_vcRound.investors[investor], "Investor already added");
        
//         _vcRound.investors[investor] = true;
//         _vcRound.investorNumber++;
        
//         emit InvestorAdded("VC", investor);
//     }

//     /**
//      * @dev Removes an investor from the VC round whitelist
//      * @param investor Address to be removed
//      */
//     function removeVCInvestor(address investor) external onlyOwner {
//         require(_vcRound.investors[investor], "Investor not found");
        
//         _vcRound.investors[investor] = false;
//         _vcRound.investorNumber--;
        
//         emit InvestorRemoved("VC", investor);
//     }

//     /**
//      * @dev Adds an investor to the Private round whitelist
//      */
//     function addPrivateInvestor(address investor) external onlyOwner {
//         require(investor != address(0), "Invalid investor address");
//         require(!_privateRound.investors[investor], "Investor already added");
        
//         _privateRound.investors[investor] = true;
//         _privateRound.investorNumber++;
        
//         emit InvestorAdded("Private", investor);
//     }

//     /**
//      * @dev Removes an investor from the Private round whitelist
//      */
//     function removePrivateInvestor(address investor) external onlyOwner {
//         require(_privateRound.investors[investor], "Investor not found");
        
//         _privateRound.investors[investor] = false;
//         _privateRound.investorNumber--;
        
//         emit InvestorRemoved("Private", investor);
//     }

//     /**
//      * @dev Main function for token purchase
//      * @param saleType Type of sale round ("VC", "Private", "Public")
//      */
//     function tokenSale(string memory saleType) external payable nonReentrant whenNotPaused {
//         require(msg.value > 0, "Amount must be greater than 0");
        
//         uint256 tokenAmount;
//         bytes32 saleTypeHash = keccak256(abi.encodePacked(saleType));
        
//         if(saleTypeHash == keccak256(abi.encodePacked("VC"))) {
//             handleVCSale(tokenAmount);
//         } 
//         else if(saleTypeHash == keccak256(abi.encodePacked("Private"))) {
//             handlePrivateSale(tokenAmount);
//         } 
//         else if(saleTypeHash == keccak256(abi.encodePacked("Public"))) {
//             handlePublicSale(tokenAmount);
//         } 
//         else {
//             require(false, "Invalid sale type");
//         }
        
//         emit TokensPurchased(msg.sender, tokenAmount, saleType);
//     }

//     /**
//      * @dev Internal function to handle VC round sale
//      */
//     function handleVCSale(uint256 tokenAmount) internal {
//         require(_vcRound.isActive, "VC round is not active");   
//         require(_vcRound.investors[msg.sender], "Not a VC investor");
        
//         tokenAmount = calculateTokenAmount(_vcRound.rate);
        
//         require(_vcRound.totalTokenSold + tokenAmount <= _vcRound.totalTokenLimit, "Exceeds round limit");
//         require(_vcRound.saleAmount[msg.sender] + tokenAmount <= _vcRound.saleLimitPerAddress, "Exceeds personal limit");
        
//         _vcRound.totalTokenSold += tokenAmount;
//         _vcRound.saleAmount[msg.sender] += tokenAmount;
        
//         processTokenPurchase(msg.sender, tokenAmount, _vcRound.tgePercentage, _vcRound.cliff, _vcRound.duration);
//     }

//     /**
//      * @dev Internal function to handle Private round sale
//      */
//     function handlePrivateSale(uint256 tokenAmount) internal {
//         require(_privateRound.isActive, "Private round is not active");   
//         require(_privateRound.investors[msg.sender], "Not a Private investor");
        
//         tokenAmount = calculateTokenAmount(_privateRound.rate);
        
//         require(_privateRound.totalTokenSold + tokenAmount <= _privateRound.totalTokenLimit, "Exceeds round limit");
//         require(_privateRound.saleAmount[msg.sender] + tokenAmount <= _privateRound.saleLimitPerAddress, "Exceeds personal limit");
        
//         _privateRound.totalTokenSold += tokenAmount;
//         _privateRound.saleAmount[msg.sender] += tokenAmount;
        
//         processTokenPurchase(
//             msg.sender, 
//             tokenAmount, 
//             _privateRound.tgePercentage, 
//             _privateRound.cliff, 
//             _privateRound.duration
//         );
//     }

//     /**
//      * @dev Internal function to handle Public round sale
//      */
//     function handlePublicSale(uint256 tokenAmount) internal {
//         require(_publicRound.isActive, "Public round is not active");   
        
//         tokenAmount = calculateTokenAmount(_publicRound.rate);
        
//         require(_publicRound.totalTokenSold + tokenAmount <= _publicRound.totalTokenLimit, "Exceeds round limit");
//         require(_publicRound.saleAmount[msg.sender] + tokenAmount <= _publicRound.saleLimitPerAddress, "Exceeds personal limit");
        
//         _publicRound.totalTokenSold += tokenAmount;
//         _publicRound.saleAmount[msg.sender] += tokenAmount;
        
//         processTokenPurchase(
//             msg.sender, 
//             tokenAmount, 
//             _publicRound.tgePercentage, 
//             _publicRound.cliff, 
//             _publicRound.duration
//         );
//     }

//     /**
//      * @dev Calculates token amount based on ETH sent and rate
//      */
//     function calculateTokenAmount(uint256 rate) internal view returns (uint256) {
//     require(rate > 0, "Invalid rate");
//     return msg.value * (10 ** TOKEN_DECIMALS) / rate;
// }

//     /**
//      * @dev Processes token purchase and vesting setup
//      */
//     function processTokenPurchase(
//         address buyer, 
//         uint256 amount, 
//         uint256 tgePercentage,
//         uint256 cliff,
//         uint256 duration
//     ) internal {
//         require(_token.balanceOf(address(this)) >= amount, "Insufficient token balance");
//         require(_token.transfer(address(_vestingContract), amount), "Token transfer failed");
        
//         _vestingContract.addBeneficiary(
//             buyer,
//             amount,
//             tgePercentage,
//             cliff,
//             duration
//         );
//     }

//     function getUserInvestment(string memory saleType, address user) public view returns (uint256){
//         bytes32 saleTypeHash = keccak256(abi.encodePacked(saleType));
//         if(saleTypeHash == keccak256(abi.encodePacked("VC"))) {
//             return _vcRound.saleAmount[user];
//         } 
//         else if(saleTypeHash == keccak256(abi.encodePacked("Private"))) {
//             return _privateRound.saleAmount[user];
//         } 
//         else if(saleTypeHash == keccak256(abi.encodePacked("Public"))) {
//             return _publicRound.saleAmount[user];
//         } 
//         else {
//             return 0;
//         }
//     }

//     /**
//      * @dev Emergency withdrawal of ETH by owner
//      */
//     function withdrawFundsBack() external onlyOwner {
//         uint256 balance = address(this).balance;
//         require(balance > 0, "No funds to withdraw");
        
//         payable(owner()).transfer(balance);
//         emit EmergencyWithdraw(owner(), balance);
//     }

//     /**
//      * @dev Withdraws remaining tokens back to owner
//      */
//     function withdrawTokensBack() external onlyOwner {
//         uint256 balance = _token.balanceOf(address(this));
//         require(balance > 0, "No tokens to withdraw");
        
//         require(_token.transfer(owner(), balance), "Token transfer failed");
//         emit EmergencyWithdraw(owner(), balance);
//     }

//     /**
//      * @dev Pauses all token sale operations
//      */
//     function pause() external onlyOwner {
//         _pause();
//     }

//     /**
//      * @dev Unpauses all token sale operations
//      */
//     function unpause() external onlyOwner {
//         _unpause();
//     }
// }