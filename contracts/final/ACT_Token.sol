// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ActiveEarthToken
 * @dev ERC20 token with cap, burnable functionality, and guard-based ownership transfer control.
 */
contract ActiveEarthToken is ERC20Capped, ERC20Burnable, Ownable, ReentrancyGuard {
    address private _guard1;
    address private _guard2;
    bool private _guardDecision;

    mapping(address => bool) public guards;

    event Burn(address indexed from, uint256 amount);
    event Mint(address indexed to, uint256 amount);

    error InsufficientBalance(address account, uint256 requested, uint256 available);
    error Unauthorized(address caller);

    /**
     * @dev Constructor initializes the token with a name, symbol, cap, initial supply, and guard addresses.
     * @param name Name of the token.
     * @param symbol Symbol of the token.
     * @param cap Maximum token supply cap.
     * @param initialSupply Initial token supply to mint.
     * @param guard1 First guard address for ownership control.
     * @param guard2 Second guard address for ownership control.
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        uint256 initialSupply,
        address guard1,
        address guard2
    ) ERC20(name, symbol) ERC20Capped(cap) Ownable(msg.sender) {
        require(cap > 0, "Cap must be greater than 0");
        require(initialSupply <= cap, "Initial supply cannot exceed cap");
        require(guard1 != address(0) && guard2 != address(0), "Guard addresses cannot be zero");

        _guard1 = guard1;
        _guard2 = guard2;
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Overridden _update function to integrate both ERC20 and ERC20Capped logic.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }

    /**
     * @dev Allows the owner to mint new tokens.
     * @param to Address to receive the minted tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner nonReentrant {
        require(to != address(0), "Destination address is not valid!");
        require(amount > 0, "Amount should be greater than zero!");
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /**
     * @dev Returns the remaining token supply that can still be minted.
     * @return Remaining mintable supply.
     */
    function circulationSupply() public view returns (uint256) {
        return cap() - totalSupply();
    }

    /**
     * @dev Transfers ownership if both guards approve the operation.
     * @param newOwner Address of the new owner.
     */
    function transferOwnership(address newOwner) public override nonReentrant {
        require(_guardDecision, "Ownership transfer not approved by guards");
        require(newOwner != address(0), "New owner address is invalid");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Allows guards to pass their decisions and control ownership transfer.
     * @param decision Guard's decision to approve (true) or reject (false) the transfer.
     * @return Current combined decision of both guards.
     */
    function guardPass(bool decision) public nonReentrant returns (bool) {
        require(msg.sender == _guard1 || msg.sender == _guard2, "Caller is not a guard");
        guards[msg.sender] = decision;

        // Combine decisions from both guards
        _guardDecision = guards[_guard1] && guards[_guard2];
        return _guardDecision;
    }

    /**
     * @dev Prevents renouncing ownership by overriding the function.
     */
    function renounceOwnership() public view override onlyOwner {
        revert("Renouncing ownership is disabled");
    }

    /**
     * @dev Fallback function to accept Ether directly.
     */
    receive() external payable {
        // Ether receipt logic (if needed)
    }
}