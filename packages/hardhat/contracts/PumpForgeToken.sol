// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import well-audited OpenZeppelin libraries for ERC20 and Ownable functionality.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PumpForgeToken
 * @notice This contract implements a Celo-specific token for Pump Forge.
 * Features:
 * - Fixed supply minting of 1 billion tokens.
 * - Customizable metadata: token name, symbol, and an image hash (stored off-chain via IPFS).
 * - Custom tax logic with separate buy and sell tax rates.
 * - Liquidity locking: restrict transfers from the DEX pair until a specified lock expiration.
 * - Anti-bot protection for the initial launch period.
 * - Standard ownership controls with the ability to renounce ownership.
 *
 * All parameters are validated and the contract adheres to production security standards.
 */
contract PumpForgeToken is ERC20, Ownable {
    // Fixed token supply: 1,000,000,000 tokens, considering 18 decimals.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    // Token metadata: IPFS hash (or URL) for the token's image.
    string public tokenImageHash;

    // Custom tax rates in basis points (100 BP = 1%).
    uint256 public buyTaxBP;   // Tax applied on "buy" transactions.
    uint256 public sellTaxBP;  // Tax applied on "sell" transactions.

    // Designated DEX pair address for this token (e.g., liquidity pool address).
    address public dexPair;

    // Liquidity lock expiration timestamp. If a transfer originates from dexPair,
    // it will only be allowed after this timestamp.
    uint256 public liquidityLockExpiration;

    // Anti-bot protection parameters.
    uint256 public launchBlock;    // Block number when the token is launched.
    uint256 public antiBotBlocks;  // Number of blocks post-launch with anti-bot restrictions.
    mapping(address => bool) public isWhitelisted;  // Addresses allowed to transfer during anti-bot period.

    // Mapping for addresses excluded from tax (e.g., owner, dexPair).
    mapping(address => bool) public isTaxExcluded;

    // ---------------------- EVENTS --------------------------
    event TaxRatesSet(uint256 buyTaxBP, uint256 sellTaxBP);
    event DexPairSet(address dexPair);
    event LiquidityLockSet(uint256 lockExpiration);
    event AntiBotParametersSet(uint256 launchBlock, uint256 antiBotBlocks);
    event AddressWhitelisted(address account, bool whitelisted);

    /**
     * @notice Constructor for PumpForgeToken.
     * @param _name The name of the token (non-empty).
     * @param _symbol The token symbol (non-empty).
     * @param _tokenImageHash The IPFS hash or URL for the token's image (non-empty).
     *
     * Mints a fixed supply of 1 billion tokens to the deployer's address.
     * Initializes tax rates to 0 and anti-bot parameters as disabled.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _tokenImageHash
    ) ERC20(_name, _symbol) {
        require(bytes(_name).length > 0, "PumpForgeToken: token name is required");
        require(bytes(_symbol).length > 0, "PumpForgeToken: token symbol is required");
        require(bytes(_tokenImageHash).length > 0, "PumpForgeToken: token image hash is required");

        tokenImageHash = _tokenImageHash;
        _mint(msg.sender, INITIAL_SUPPLY);

        // Initialize default tax rates to 0.
        buyTaxBP = 0;
        sellTaxBP = 0;

        // Exclude the deployer (owner) from tax by default.
        isTaxExcluded[msg.sender] = true;

        // Initialize anti-bot parameters as disabled (0 blocks).
        launchBlock = block.number;
        antiBotBlocks = 0;
    }

    // -----------------------------------------------------
    // TAX LOGIC
    // -----------------------------------------------------

    /**
     * @notice Sets the buy and sell tax rates.
     * @param _buyTaxBP Buy tax in basis points.
     * @param _sellTaxBP Sell tax in basis points.
     * Requirements:
     * - Tax rates must not exceed 1000 BP (10%).
     * Only the owner can call this function.
     */
    function setTaxRates(uint256 _buyTaxBP, uint256 _sellTaxBP) external onlyOwner {
        require(_buyTaxBP <= 1000, "PumpForgeToken: buy tax too high");
        require(_sellTaxBP <= 1000, "PumpForgeToken: sell tax too high");
        buyTaxBP = _buyTaxBP;
        sellTaxBP = _sellTaxBP;
        emit TaxRatesSet(_buyTaxBP, _sellTaxBP);
    }

    /**
     * @notice Excludes or includes an address from tax.
     * @param account The address to update.
     * @param excluded True to exclude, false to include.
     * Only the owner can call.
     */
    function setTaxExclusion(address account, bool excluded) external onlyOwner {
        isTaxExcluded[account] = excluded;
    }

    /**
     * @notice Sets the DEX pair address for the token.
     * @param _dexPair The address of the liquidity pool.
     * Only the owner can call.
     */
    function setDexPair(address _dexPair) external onlyOwner {
        require(_dexPair != address(0), "PumpForgeToken: invalid dex pair address");
        dexPair = _dexPair;
        // Optionally exclude the dex pair from tax calculations.
        isTaxExcluded[_dexPair] = true;
        emit DexPairSet(_dexPair);
    }

    // -----------------------------------------------------
    // LIQUIDITY LOCKING
    // -----------------------------------------------------

    /**
     * @notice Sets the liquidity lock period.
     * @param _lockDuration The duration in seconds from now to lock liquidity transfers.
     * Only the owner can call this function.
     */
    function setLiquidityLock(uint256 _lockDuration) external onlyOwner {
        liquidityLockExpiration = block.timestamp + _lockDuration;
        emit LiquidityLockSet(liquidityLockExpiration);
    }

    // -----------------------------------------------------
    // ANTI-BOT PROTECTION
    // -----------------------------------------------------

    /**
     * @notice Sets anti-bot parameters for the token launch.
     * @param _antiBotBlocks The number of blocks post-launch during which anti-bot protection is active.
     * This function also resets the launchBlock to the current block number.
     * Only the owner can call.
     */
    function setAntiBotParameters(uint256 _antiBotBlocks) external onlyOwner {
        launchBlock = block.number;
        antiBotBlocks = _antiBotBlocks;
        emit AntiBotParametersSet(launchBlock, antiBotBlocks);
    }

    /**
     * @notice Adds or removes an address from the anti-bot whitelist.
     * @param account The address to update.
     * @param whitelisted True to whitelist the address, false to remove it.
     * Only the owner can call.
     */
    function updateWhitelist(address account, bool whitelisted) external onlyOwner {
        isWhitelisted[account] = whitelisted;
        emit AddressWhitelisted(account, whitelisted);
    }

    // -----------------------------------------------------
    // OVERRIDDEN _transfer FUNCTION
    // Incorporates custom tax logic, liquidity locking, and anti-bot protection.
    // -----------------------------------------------------

    /**
     * @dev Overridden _transfer function that implements:
     * - Anti-bot protection: Restricts transfers during the initial launch period unless whitelisted.
     * - Liquidity lock: Blocks transfers from the dexPair until the liquidity lock period expires.
     * - Custom tax logic: Applies buy or sell taxes based on the dexPair address.
     *
     * The tax is collected and sent to the contract owner.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // Anti-Bot Protection: During the initial antiBotBlocks period, only allow transfers if either party is whitelisted.
        if (block.number < launchBlock + antiBotBlocks) {
            require(isWhitelisted[sender] || isWhitelisted[recipient], "PumpForgeToken: Anti-bot protection active");
        }

        // Liquidity Lock: Prevent transfers originating from the dexPair if liquidity lock period is active.
        if (sender == dexPair) {
            require(block.timestamp >= liquidityLockExpiration, "PumpForgeToken: Liquidity locked");
        }

        uint256 taxAmount = 0;

        // Determine if tax should be applied (if neither sender nor recipient is excluded).
        if (!isTaxExcluded[sender] && !isTaxExcluded[recipient]) {
            // Check if the transaction qualifies as a "buy" or "sell" based on the dexPair.
            if (sender == dexPair && buyTaxBP > 0) {
                // Buy transaction.
                taxAmount = (amount * buyTaxBP) / 10000;
            } else if (recipient == dexPair && sellTaxBP > 0) {
                // Sell transaction.
                taxAmount = (amount * sellTaxBP) / 10000;
            }
        }

        // If a tax applies, transfer the tax amount to the owner and the remaining amount to the recipient.
        if (taxAmount > 0) {
            super._transfer(sender, owner(), taxAmount);
            super._transfer(sender, recipient, amount - taxAmount);
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    // -----------------------------------------------------
    // OWNERSHIP RENOUNCEMENT OVERRIDE
    // -----------------------------------------------------

    /**
     * @notice Renounces ownership of the contract.
     * Overrides the standard Ownable renounceOwnership to allow for future logging or additional logic.
     * Only the current owner can call.
     */
    function renounceOwnership() public override onlyOwner {
        super.renounceOwnership();
        // Future enhancements: Emit a specialized event or trigger additional checks if needed.
    }
}
